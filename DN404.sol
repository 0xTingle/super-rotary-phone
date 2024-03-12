// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibBitmap} from "solady/utils/LibBitmap.sol";

/// @title DN404
/// @notice DN404 is a hybrid ERC20 and ERC721 implementation that mints
/// and burns NFTs based on an account's ERC20 token balance.
///
/// @author vectorized.eth (@optimizoor)
/// @author Quit (@0xQuit)
/// @author Michael Amadi (@AmadiMichaels)
/// @author cygaar (@0xCygaar)
/// @author Thomas (@0xjustadev)
/// @author Harrison (@PopPunkOnChain)
///
/// @dev Note:
/// - The ERC721 data is stored in this base DN404 contract, however a
///   DN404Mirror contract ***MUST*** be deployed and linked during
///   initialization.
abstract contract DN404 {
    using LibBitmap for LibBitmap.Bitmap;
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @dev Emitted when `target` sets their skipNFT flag to `status`.
    event SkipNFTSet(address indexed target, bool status);

    /// @dev `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    /// @dev `keccak256(bytes("SkipNFTSet(address,bool)"))`.
    uint256 private constant _SKIP_NFT_SET_EVENT_SIGNATURE =
        0xb5a1de456fff688115a4f75380060c23c8532d14ff85f687cc871456d6420393;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CUSTOM ERRORS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Thrown when attempting to double-initialize the contract.
    error DNAlreadyInitialized();

    /// @dev Thrown when attempting to transfer or burn more tokens than sender's balance.
    error InsufficientBalance();

    /// @dev Thrown when a spender attempts to transfer tokens with an insufficient allowance.
    error InsufficientAllowance();

    /// @dev Thrown when minting an amount of tokens that would overflow the max tokens.
    error TotalSupplyOverflow();

    /// @dev The unit cannot be zero.
    error UnitIsZero();

    /// @dev Thrown when the caller for a fallback NFT function is not the mirror contract.
    error SenderNotMirror();

    /// @dev Thrown when attempting to transfer tokens to the zero address.
    error TransferToZeroAddress();

    /// @dev Thrown when the mirror address provided for initialization is the zero address.
    error MirrorAddressIsZero();

    /// @dev Thrown when the link call to the mirror contract reverts.
    error LinkMirrorContractFailed();

    /// @dev Thrown when setting an NFT token approval
    /// and the caller is not the owner or an approved operator.
    error ApprovalCallerNotOwnerNorApproved();

    /// @dev Thrown when transferring an NFT
    /// and the caller is not the owner or an approved operator.
    error TransferCallerNotOwnerNorApproved();

    /// @dev Thrown when transferring an NFT and the from address is not the current owner.
    error TransferFromIncorrectOwner();

    /// @dev Thrown when checking the owner or approved address for a non-existent NFT.
    error TokenDoesNotExist();

    /// @dev Thrown when exchanging the NFTs that locked.
    error ExchangeTokenLocked();

    /// @dev Thrown when exchanging the same NFTs
    error ExchangeSameToken();

    /// @dev Thrown when attempting to lock the NFTs that locked,
    ///      or to unlock the NFTs that unlocked.
    error TokenLockStatusNoChange();

    /// @dev Thrown when transferring tokens but the balance is insufficient to to maintain locked NFTs.
    error InsufficientBalanceToMaintainLockedTokens();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The flag to denote that the address data is initialized.
    uint8 internal constant _ADDRESS_DATA_INITIALIZED_FLAG = 1 << 0;

    /// @dev The flag to denote that the address should skip NFTs.
    uint8 internal constant _ADDRESS_DATA_SKIP_NFT_FLAG = 1 << 1;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Struct containing an address's token data and settings.
    struct AddressData {
        // Auxiliary data.
        uint56 aux;
        // Flags for `initialized` and `skipNFT`.
        uint8 flags;
        // The alias for the address. Zero means absence of an alias.
        uint32 addressAlias;
        // The number of NFT tokens locked.
        uint32 lockedLength;
        // The number of NFT tokens owned.
        uint32 ownedLength;
        // The token balance in wei.
        uint96 balance;
        // snapshot of `accFeePerNFT` when the account fee accrued
        uint96 feePerNFTSnap;
    }

    /// @dev A uint32 map in storage.
    struct Uint32Map {
        mapping(uint256 => uint256) map;
    }

    /// @dev A struct to wrap a uint256 in storage.
    struct Uint256Ref {
        uint256 value;
    }

    /// @dev Struct containing the base token contract storage.
    struct DN404Storage {
        // Current number of address aliases assigned.
        uint32 numAliases;
        // Next NFT ID to assign for a mint.
        uint32 nextTokenId;
        // Total number of NFT IDs in the burned pool.
        uint32 burnedPoolSize;
        // Total supply of minted NFTs.
        uint32 totalNFTSupply;
        // Total supply of tokens.
        uint96 totalSupply;
        // Address of the NFT mirror contract.
        address mirrorERC721;
        // Mapping of a user alias number to their address.
        mapping(uint32 => address) aliasToAddress;
        // Mapping of user operator approvals for NFTs.
        mapping(address => mapping(address => Uint256Ref)) operatorApprovals;
        // Mapping of NFT approvals to approved operators.
        mapping(uint256 => address) nftApprovals;
        // Bitmap of whether an non-zero NFT approval may exist.
        LibBitmap.Bitmap mayHaveNFTApproval;
        // Mapping of user allowances for ERC20 spenders.
        mapping(address => mapping(address => Uint256Ref)) allowance;
        // Mapping of NFT IDs owned by an address.
        mapping(address => Uint32Map) owned;
        // Mapping of NFT token IDs locked by an address.
        mapping(address => Uint32Map) locked;
        // The pool of burned NFT IDs.
        Uint32Map burnedPool;
        // Even indices: owner aliases. Odd indices: owned indices.
        // if NFT token was locked, owned indices are ref to `locked`, otherwise `owned`
        Uint32Map oo;
        // Mapping of user account AddressData.
        mapping(address => AddressData) addressData;
        // Mapping of NFT token to locked flag
        LibBitmap.Bitmap tokenLocks;
        // The number of NFT tokens locked globally.
        uint32 numLockedNFT;
        // The number of NFT tokens approved to `this` globally.
        uint32 numExchangableNFT;
        // Fee rate to charged per NFT when exchange unlocking NFTs
        uint16 exchangeNFTFeeBips;
        // accumulated fee per unlocked NFT should receive
        uint96 accFeePerNFT;
    }

    /// @dev Returns a storage pointer for DN404Storage.
    function _getDN404Storage() internal pure virtual returns (DN404Storage storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            // `uint72(bytes9(keccak256("DN404_STORAGE")))`.
            $.slot := 0xa20d6e21d0e5255308 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         INITIALIZER                        */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the DN404 contract with an
    /// `initialTokenSupply`, `initialTokenOwner` and `mirror` NFT contract address.
    function _initializeDN404(
        uint256 initialTokenSupply,
        address initialSupplyOwner,
        address mirror
    ) internal virtual {
        DN404Storage storage $ = _getDN404Storage();

        if ($.nextTokenId != 0) revert DNAlreadyInitialized();

        if (mirror == address(0)) revert MirrorAddressIsZero();

        /// @solidity memory-safe-assembly
        assembly {
            // Make the call to link the mirror contract.
            mstore(0x00, 0x0f4599e5) // `linkMirrorContract(address)`.
            mstore(0x20, caller())
            if iszero(and(eq(mload(0x00), 1), call(gas(), mirror, 0, 0x1c, 0x24, 0x00, 0x20))) {
                mstore(0x00, 0xd125259c) // `LinkMirrorContractFailed()`.
                revert(0x1c, 0x04)
            }
        }

        $.nextTokenId = 1;
        $.mirrorERC721 = mirror;

        if (_unit() == 0) revert UnitIsZero();

        if (initialTokenSupply != 0) {
            if (initialSupplyOwner == address(0)) {
                revert TransferToZeroAddress();
            }
            if (_totalSupplyOverflows(initialTokenSupply)) {
                revert TotalSupplyOverflow();
            }

            $.totalSupply = uint96(initialTokenSupply);
            AddressData storage initialOwnerAddressData = _addressData(initialSupplyOwner);
            initialOwnerAddressData.balance = uint96(initialTokenSupply);

            /// @solidity memory-safe-assembly
            assembly {
                // Emit the {Transfer} event.
                mstore(0x00, initialTokenSupply)
                log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, initialSupplyOwner)))
            }

            _setSkipNFT(initialSupplyOwner, true);
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*               BASE UNIT FUNCTION TO OVERRIDE               */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Amount of token balance that is equal to one NFT.
    function _unit() internal view virtual returns (uint256) {
        return 10 ** 18;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*               METADATA FUNCTIONS TO OVERRIDE               */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the name of the token.
    function name() public view virtual returns (string memory);

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual returns (string memory);

    /// @dev Returns the Uniform Resource Identifier (URI) for token `id`.
    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ERC20 OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the decimals places of the token. Always 18.
    function decimals() public pure returns (uint8) {
        return 18;
    }

    /// @dev Returns the amount of tokens in existence.
    function totalSupply() public view virtual returns (uint256) {
        return uint256(_getDN404Storage().totalSupply);
    }

    /// @dev Returns the amount of tokens owned by `owner`.
    function balanceOf(address owner) public view virtual returns (uint256) {
        return _getDN404Storage().addressData[owner].balance;
    }

    /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender) public view returns (uint256) {
        return _getDN404Storage().allowance[owner][spender].value;
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @dev Transfer `amount` tokens from the caller to `to`.
    ///
    /// Will burn sender NFTs if balance after transfer is less than
    /// the amount required to support the current NFT balance.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    ///
    /// Emits a {Transfer} event.
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        DN404Storage storage $ = _getDN404Storage();
        _pullFeeForTwo($, msg.sender, to);
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @dev Transfers `amount` tokens from `from` to `to`.
    ///
    /// Note: Does not update the allowance if it is the maximum uint256 value.
    ///
    /// Will burn sender NFTs if balance after transfer is less than
    /// the amount required to support the current NFT balance.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    /// - The caller must have at least `amount` of allowance to transfer the tokens of `from`.
    ///
    /// Emits a {Transfer} event.
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        DN404Storage storage $ = _getDN404Storage();
        Uint256Ref storage a = $.allowance[from][msg.sender];

        uint256 allowed = a.value;
        if (allowed != type(uint256).max) {
            if (amount > allowed) revert InsufficientAllowance();
            unchecked {
                a.value = allowed - amount;
            }
        }
        _pullFeeForTwo($, from, to);
        _transfer(from, to, amount);
        return true;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                INTERNAL TRANSFER FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Moves `amount` of tokens from `from` to `to`.
    ///
    /// Will burn sender NFTs if balance after transfer is less than
    /// the amount required to support the current NFT balance.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///
    /// Emits a {Transfer} event.
    function _transfer(address from, address to, uint256 amount) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        _TransferTemps memory t;
        t.fromOwnedLength = fromAddressData.ownedLength;
        t.toOwnedLength = toAddressData.ownedLength;
        t.totalSupply = $.totalSupply;

        if (amount > (t.fromBalance = fromAddressData.balance)) {
            revert InsufficientBalance();
        }

        unchecked {
            t.fromBalance -= amount;

            t.fromLockedLength = fromAddressData.lockedLength;
            // need enough token to maintain locked NFTs
            if (t.fromBalance < t.fromLockedLength * _unit()) {
                revert InsufficientBalanceToMaintainLockedTokens();
            }

            fromAddressData.balance = uint96(t.fromBalance);
            toAddressData.balance = uint96(t.toBalance = toAddressData.balance + amount);

            t.numNFTBurns =
                _zeroFloorSub(t.fromOwnedLength + t.fromLockedLength, t.fromBalance / _unit());

            if (toAddressData.flags & _ADDRESS_DATA_SKIP_NFT_FLAG == 0) {
                if (from == to) t.toOwnedLength = t.fromOwnedLength - t.numNFTBurns;
                t.numNFTMints = _zeroFloorSub(
                    t.toBalance / _unit(),
                    t.toOwnedLength + toAddressData.lockedLength // balance needed for locked and owned
                );
            }

            {
                // cache `address(this)` aspprovals
                mapping(address => Uint256Ref) storage thisOperatorApprovals =
                    $.operatorApprovals[address(this)];
                // `from` burns NFTs
                if (thisOperatorApprovals[from].value != 0) {
                    $.numExchangableNFT -= uint32(t.numNFTBurns);
                }
                // `to`mints NFTs
                if (thisOperatorApprovals[to].value != 0) {
                    $.numExchangableNFT += uint32(t.numNFTMints);
                }
            }

            $.totalNFTSupply = uint32(uint256($.totalNFTSupply) + t.numNFTMints - t.numNFTBurns);
            Uint32Map storage oo = $.oo;
            {
                uint256 n = _min(t.numNFTBurns, t.numNFTMints);
                if (n != 0) {
                    t.numNFTBurns -= n;
                    t.numNFTMints -= n;

                    if (from == to) {
                        t.toOwnedLength += n;
                    } else {
                        _DNDirectLogs memory directLogs = _directLogsMalloc(n, from, to);
                        Uint32Map storage fromOwned = $.owned[from];
                        Uint32Map storage toOwned = $.owned[to];
                        uint32 toAlias = _registerAndResolveAlias(toAddressData, to);
                        // Direct transfer loop.
                        do {
                            uint256 id = _get(fromOwned, --t.fromOwnedLength);
                            _set(toOwned, t.toOwnedLength, uint32(id));
                            _setOwnerAliasAndOwnedIndex(oo, id, toAlias, uint32(t.toOwnedLength++));
                            _removeNFTApproval($, id);
                            _directLogsAppend(directLogs, id);
                        } while (--n != 0);

                        _directLogsSend(directLogs, $.mirrorERC721);
                        fromAddressData.ownedLength = uint32(t.fromOwnedLength);
                        toAddressData.ownedLength = uint32(t.toOwnedLength);
                    }
                }
            }

            _PackedLogs memory packedLogs = _packedLogsMalloc(t.numNFTBurns + t.numNFTMints);
            uint256 burnedPoolSize = $.burnedPoolSize;
            if (t.numNFTBurns != 0) {
                _packedLogsSet(packedLogs, from, 1);
                Uint32Map storage fromOwned = $.owned[from];
                uint256 fromIndex = t.fromOwnedLength;
                uint256 fromEnd = fromIndex - t.numNFTBurns;
                fromAddressData.ownedLength = uint32(fromEnd);
                // Burn loop.
                do {
                    uint256 id = _get(fromOwned, --fromIndex);
                    _setOwnerAliasAndOwnedIndex(oo, id, 0, 0);
                    _set($.burnedPool, burnedPoolSize++, uint32(id));
                    _removeNFTApproval($, id);
                    _packedLogsAppend(packedLogs, id);
                } while (fromIndex != fromEnd);
            }

            if (t.numNFTMints != 0) {
                _packedLogsSet(packedLogs, to, 0);
                uint256 nextTokenId = $.nextTokenId;
                Uint32Map storage toOwned = $.owned[to];
                uint256 toIndex = t.toOwnedLength;
                uint256 toEnd = toIndex + t.numNFTMints;
                uint32 toAlias = _registerAndResolveAlias(toAddressData, to);
                toAddressData.ownedLength = uint32(toEnd);
                // Mint loop.
                do {
                    uint256 id;
                    if (burnedPoolSize != 0) {
                        id = _get($.burnedPool, --burnedPoolSize);
                    } else {
                        id = nextTokenId;
                        nextTokenId = id + 1;
                    }
                    _set(toOwned, toIndex, uint32(id));
                    _setOwnerAliasAndOwnedIndex(oo, id, toAlias, uint32(toIndex++));
                    _packedLogsAppend(packedLogs, id);
                } while (toIndex != toEnd);

                $.nextTokenId = uint32(nextTokenId);
            }

            if (packedLogs.logs.length != 0) {
                $.burnedPoolSize = uint32(burnedPoolSize);
                _packedLogsSend(packedLogs, $.mirrorERC721);
            }
            /// @solidity memory-safe-assembly
            assembly {
                // Emit the {Transfer} event.
                mstore(0x00, amount)
                // forgefmt: disable-next-item
                log3(
                    0x00,
                    0x20,
                    _TRANSFER_EVENT_SIGNATURE,
                    shr(96, shl(96, from)),
                    shr(96, shl(96, to))
                )
            }
        }
    }

    /// @dev Transfers token `id` from `from` to `to`.
    ///
    /// Requirements:
    ///
    /// - Call must originate from the mirror contract.
    /// - Token `id` must exist.
    /// - `from` must be the owner of the token.
    /// - `to` cannot be the zero address.
    ///   `msgSender` must be the owner of the token, or be approved to manage the token.
    ///
    /// Emits a {Transfer} event.
    function _transferFromNFT(address from, address to, uint256 id, address msgSender)
        internal
        virtual
    {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();
        Uint32Map storage oo = $.oo;

        if (from != $.aliasToAddress[_get(oo, _ownershipIndex(id))]) {
            revert TransferFromIncorrectOwner();
        }

        if (msgSender != from) {
            if ($.operatorApprovals[msgSender][from].value == 0) {
                if (msgSender != $.nftApprovals[id]) {
                    revert TransferCallerNotOwnerNorApproved();
                }
            }
        }

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        uint256 unit = _unit();

        fromAddressData.balance -= uint96(unit);

        unchecked {
            toAddressData.balance += uint96(unit);

            _removeNFTApproval($, id);

            uint32 toTransferIdx = _get(oo, _ownedIndex(id));
            if (LibBitmap.get($.tokenLocks, id)) {
                // operate `locked` map
                // delete transferred NFT
                _delNFTAt($.locked[from], oo, toTransferIdx, --fromAddressData.lockedLength);
            } else {
                // The unlocked NFTs amount of account `from` will decrease, collecting fees first
                _pullFeeForTwo($, from, from);
                // `from` lock 1 NFT
                if ($.operatorApprovals[address(this)][from].value != 0) {
                    --$.numExchangableNFT;
                }

                // operate `owned` map
                // delete transferred NFT
                _delNFTAt($.owned[from], oo, toTransferIdx, --fromAddressData.ownedLength);

                // lock
                LibBitmap.setTo($.tokenLocks, id, true);
                ++$.numLockedNFT;
            }

            // transfer ownership
            // lock the NFT by default for ERC721 transfer
            uint256 n = toAddressData.lockedLength++;
            _set($.locked[to], n, uint32(id));
            _setOwnerAliasAndOwnedIndex(
                oo, id, _registerAndResolveAlias(toAddressData, to), uint32(n)
            );
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, unit)
            // forgefmt: disable-next-item
            log3(
                0x00,
                0x20,
                _TRANSFER_EVENT_SIGNATURE,
                shr(96, shl(96, from)),
                shr(96, shl(96, to))
            )
        }
    }

    function _exchangeNFT(uint256 idX, uint256 idY, address msgSender)
        internal
        virtual
        returns (address x, address y, uint256 exchangeFee)
    {
        if (idX == idY) revert ExchangeSameToken();

        DN404Storage storage $ = _getDN404Storage();

        LibBitmap.Bitmap storage tokenLocks = $.tokenLocks;
        if (_toUint(LibBitmap.get(tokenLocks, idX)) | _toUint(LibBitmap.get(tokenLocks, idY)) != 0)
        {
            revert ExchangeTokenLocked();
        }

        x = _ownerOf(idX);
        y = _ownerOf(idY);
        mapping(address => Uint256Ref) storage thisOperatorApprovals =
            $.operatorApprovals[address(this)];
        if (x != msgSender || thisOperatorApprovals[y].value == 0) {
            revert ApprovalCallerNotOwnerNorApproved();
        }

        _removeNFTApproval($, idX);
        _removeNFTApproval($, idY);

        // collecting fees for account `x` and `y` first
        _pullFeeForTwo($, x, y);

        Uint32Map storage oo = $.oo;

        // idY to account x, then lock
        // must transfer `idY` firstly, otherwise the ownedIndex of `idX` is wrong
        AddressData storage xAddressData = _addressData(x);
        {
            uint256 xIndex = _get(oo, _ownedIndex(idX));
            // remove NFT `idX` from account `x`
            _delNFTAt($.owned[x], oo, xIndex, --xAddressData.ownedLength);
        }

        // snapshot owned index of `idY`
        uint256 yIndex = _get(oo, _ownedIndex(idY));

        {
            // append `idY` to `locked`
            uint256 n = xAddressData.lockedLength++;
            _set($.locked[x], n, uint32(idY));
            _setOwnerAliasAndOwnedIndex(oo, idY, xAddressData.addressAlias, uint32(n));

            // lock `idY`
            LibBitmap.setTo(tokenLocks, idY, true);
            ++$.numLockedNFT;
        }

        // idX to account y
        AddressData storage yAddressData = _addressData(y);
        _setOwnerAliasAndOwnedIndex(oo, idX, yAddressData.addressAlias, uint32(yIndex));
        _set($.owned[y], yIndex, uint32(idX));

        // transfer nft first, then token, otherwise specified NFT transfer may not success
        // fee charges in percentage of the unit
        exchangeFee = $.exchangeNFTFeeBips;
        if (exchangeFee > 0) {
            unchecked {
                exchangeFee *= _unit() / 10000;
                _transfer(x, address(this), exchangeFee);
                $.accFeePerNFT += uint96(exchangeFee / $.numExchangableNFT);
            }
        }

        // x lock 1 NFT
        if (thisOperatorApprovals[x].value != 0) {
            --$.numExchangableNFT;
        }
    }

    function _pullFeeForTwo(DN404Storage storage $, address account1, address account2)
        internal
        virtual
    {
        // Cannot receive fee if `address(this)` has no operator approvals
        mapping(address => Uint256Ref) storage thisOperatorApprovals =
            $.operatorApprovals[address(this)];
        uint256 accFeePerNFT;
        if (thisOperatorApprovals[account1].value > 0) {
            accFeePerNFT = $.accFeePerNFT;
            AddressData storage addressData = $.addressData[account1];
            // only unlocked NFTs receive fee
            uint256 accrued = (accFeePerNFT - addressData.feePerNFTSnap) * (addressData.ownedLength);
            addressData.feePerNFTSnap = uint96(accFeePerNFT);
            if (accrued > 0) {
                _transfer(address(this), account1, accrued);
            }
        }
        if (account2 != account1) {
            if (thisOperatorApprovals[account2].value > 0) {
                if (accFeePerNFT == 0) {
                    accFeePerNFT = $.accFeePerNFT;
                }
                AddressData storage addressData = $.addressData[account2];
                // only unlocked NFTs receive fee
                uint256 accrued =
                    (accFeePerNFT - addressData.feePerNFTSnap) * (addressData.ownedLength);
                addressData.feePerNFTSnap = uint96(accFeePerNFT);
                if (accrued > 0) {
                    _transfer(address(this), account2, accrued);
                }
            }
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 INTERNAL APPROVE FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets `amount` as the allowance of `spender` over the tokens of `owner`.
    ///
    /// Emits a {Approval} event.
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        _getDN404Storage().allowance[owner][spender].value = amount;
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Approval} event.
            mstore(0x00, amount)
            // forgefmt: disable-next-item
            log3(
                0x00,
                0x20,
                _APPROVAL_EVENT_SIGNATURE,
                shr(96, shl(96, owner)),
                shr(96, shl(96, spender))
            )
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 DATA HITCHHIKING FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the auxiliary data for `owner`.
    /// Minting, transferring, burning the tokens of `owner` will not change the auxiliary data.
    /// Auxiliary data can be set for any address, even if it does not have any tokens.
    function _getAux(address owner) internal view virtual returns (uint56) {
        return _getDN404Storage().addressData[owner].aux;
    }

    /// @dev Set the auxiliary data for `owner` to `value`.
    /// Minting, transferring, burning the tokens of `owner` will not change the auxiliary data.
    /// Auxiliary data can be set for any address, even if it does not have any tokens.
    function _setAux(address owner, uint56 value) internal virtual {
        _getDN404Storage().addressData[owner].aux = value;
    }

    function _setExchangeNFTFeeRate(uint256 feeBips) internal virtual {
        _getDN404Storage().exchangeNFTFeeBips = uint16(feeBips);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     SKIP NFT FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns true if minting and transferring ERC20s to `owner` will skip minting NFTs.
    /// Returns false otherwise.
    function getSkipNFT(address owner) public view virtual returns (bool) {
        AddressData storage d = _getDN404Storage().addressData[owner];
        if (d.flags & _ADDRESS_DATA_INITIALIZED_FLAG == 0) {
            return _hasCode(owner);
        }
        return d.flags & _ADDRESS_DATA_SKIP_NFT_FLAG != 0;
    }

    /// @dev Sets the caller's skipNFT flag to `skipNFT`. Returns true.
    ///
    /// Emits a {SkipNFTSet} event.
    function setSkipNFT(bool skipNFT) public virtual returns (bool) {
        _setSkipNFT(msg.sender, skipNFT);
        return true;
    }

    /// @dev Internal function to set account `owner` skipNFT flag to `state`
    ///
    /// Initializes account `owner` AddressData if it is not currently initialized.
    ///
    /// Emits a {SkipNFTSet} event.
    function _setSkipNFT(address owner, bool state) internal virtual {
        AddressData storage d = _addressData(owner);
        if ((d.flags & _ADDRESS_DATA_SKIP_NFT_FLAG != 0) != state) {
            d.flags ^= _ADDRESS_DATA_SKIP_NFT_FLAG;
        }
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, iszero(iszero(state)))
            log2(0x00, 0x20, _SKIP_NFT_SET_EVENT_SIGNATURE, shr(96, shl(96, owner)))
        }
    }

    /// @dev Returns a storage data pointer for account `owner` AddressData
    ///
    /// Initializes account `owner` AddressData if it is not currently initialized.
    function _addressData(address owner) internal virtual returns (AddressData storage d) {
        d = _getDN404Storage().addressData[owner];
        unchecked {
            if (d.flags & _ADDRESS_DATA_INITIALIZED_FLAG == 0) {
                uint256 skipNFT = (_toUint(_hasCode(owner)) * _ADDRESS_DATA_SKIP_NFT_FLAG);
                d.flags = uint8(skipNFT | _ADDRESS_DATA_INITIALIZED_FLAG);
            }
        }
    }

    /// @dev Returns the `addressAlias` of account `to`.
    ///
    /// Assigns and registers the next alias if `to` alias was not previously registered.
    function _registerAndResolveAlias(AddressData storage toAddressData, address to)
        internal
        virtual
        returns (uint32 addressAlias)
    {
        DN404Storage storage $ = _getDN404Storage();
        addressAlias = toAddressData.addressAlias;
        if (addressAlias == 0) {
            unchecked {
                addressAlias = ++$.numAliases;
            }
            toAddressData.addressAlias = addressAlias;
            $.aliasToAddress[addressAlias] = to;
            if (addressAlias == 0) revert(); // Overflow.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     MIRROR OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the address of the mirror NFT contract.
    function mirrorERC721() public view virtual returns (address) {
        return _getDN404Storage().mirrorERC721;
    }

    /// @dev Returns the total NFT supply.
    function _totalNFTSupply() internal view virtual returns (uint256) {
        return _getDN404Storage().totalNFTSupply;
    }

    /// @dev Returns `owner` NFT balance.
    function _balanceOfNFT(address owner) internal view virtual returns (uint256) {
        AddressData storage addressData = _getDN404Storage().addressData[owner];
        return addressData.ownedLength + addressData.lockedLength;
    }

    /// @dev Returns the owner of token `id`.
    /// Returns the zero address instead of reverting if the token does not exist.
    function _ownerAt(uint256 id) internal view virtual returns (address) {
        DN404Storage storage $ = _getDN404Storage();
        return $.aliasToAddress[_get($.oo, _ownershipIndex(id))];
    }

    /// @dev Returns the owner of token `id`.
    ///
    /// Requirements:
    /// - Token `id` must exist.
    function _ownerOf(uint256 id) internal view virtual returns (address) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return _ownerAt(id);
    }

    /// @dev Returns if token `id` exists.
    function _exists(uint256 id) internal view virtual returns (bool) {
        return _ownerAt(id) != address(0);
    }

    /// @dev Returns the account approved to manage token `id`.
    ///
    /// Requirements:
    /// - Token `id` must exist.
    function _getApproved(uint256 id) internal view virtual returns (address) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return _getDN404Storage().nftApprovals[id];
    }

    /// @dev Sets `spender` as the approved account to manage token `id`, using `msgSender`.
    ///
    /// Requirements:
    /// - `msgSender` must be the owner or an approved operator for the token owner.
    function _approveNFT(address spender, uint256 id, address msgSender)
        internal
        virtual
        returns (address owner)
    {
        DN404Storage storage $ = _getDN404Storage();

        owner = $.aliasToAddress[_get($.oo, _ownershipIndex(id))];

        if (msgSender != owner) {
            if ($.operatorApprovals[msgSender][owner].value == 0) {
                revert ApprovalCallerNotOwnerNorApproved();
            }
        }

        $.nftApprovals[id] = spender;
        LibBitmap.setTo($.mayHaveNFTApproval, id, spender != address(0));
    }

    function _removeNFTApproval(DN404Storage storage $, uint256 id) internal virtual {
        if (LibBitmap.get($.mayHaveNFTApproval, id)) {
            LibBitmap.setTo($.mayHaveNFTApproval, id, false);
            delete $.nftApprovals[id];
        }
    }

    /// @dev Approve or remove the `operator` as an operator for `msgSender`,
    /// without authorization checks.
    function _setApprovalForAll(address operator, bool approved, address msgSender)
        internal
        virtual
    {
        DN404Storage storage $ = _getDN404Storage();
        Uint256Ref storage ref = $.operatorApprovals[operator][msgSender];
        if (operator == address(this)) {
            bool status = ref.value != 0;
            AddressData storage senderAddressData = $.addressData[msgSender];
            if (_toUint(approved) & _toUint(!status) != 0) {
                // initialize when approving
                senderAddressData.feePerNFTSnap = $.accFeePerNFT;
                $.numExchangableNFT += senderAddressData.ownedLength;
            } else if (_toUint(!approved) & _toUint(status) != 0) {
                // refresh when removing approval
                _pullFeeForTwo($, msgSender, msgSender);
                $.numExchangableNFT -= senderAddressData.ownedLength;
            }
        }
        ref.value = _toUint(approved); // `approved ? 1 : 0`
    }

    /// @dev Lock or unlock the `id`,
    /// `msgSener` should be authorized as the operator of the owner of the NFT
    function _setNFTLockState(uint256[] memory ids, bool lock, address msgSender)
        internal
        virtual
    {
        DN404Storage storage $ = _getDN404Storage();
        _pullFeeForTwo($, msgSender, msgSender);

        Uint32Map storage oo = $.oo;
        LibBitmap.Bitmap storage tokenLocks = $.tokenLocks;

        AddressData storage ownerAddressData = $.addressData[msgSender];
        Uint32Map storage ownerLocked = $.locked[msgSender];
        Uint32Map storage ownerOwned = $.owned[msgSender];
        uint32 ownerAlias = ownerAddressData.addressAlias;
        uint256 idLen = ids.length;

        for (uint256 i; i < idLen; ++i) {
            uint256 id = ids[i];

            if (_get(oo, _ownershipIndex(id)) != ownerAlias) {
                revert ApprovalCallerNotOwnerNorApproved();
            }

            uint32 ownedIndex = _get(oo, _ownedIndex(id));

            if (LibBitmap.get(tokenLocks, id) == lock) revert TokenLockStatusNoChange();

            if (!lock) {
                // already locked, to unlock
                LibBitmap.setTo(tokenLocks, id, false);

                // swap with last NFT and pop the last
                _delNFTAt(ownerLocked, oo, ownedIndex, --ownerAddressData.lockedLength);

                uint256 n = ownerAddressData.ownedLength++;
                _set(ownerOwned, n, uint32(id));
                _set(oo, _ownedIndex(id), uint32(n));
            } else {
                // not locked, to lock
                LibBitmap.setTo(tokenLocks, id, true);

                // swap with last NFT and pop the last
                _delNFTAt(ownerOwned, oo, ownedIndex, --ownerAddressData.ownedLength);

                uint256 n = ownerAddressData.lockedLength++;
                _set(ownerLocked, n, uint32(id));
                _set(oo, _ownedIndex(id), uint32(n));
            }
        }

        if (lock) $.numLockedNFT += uint32(idLen);
        else $.numLockedNFT -= uint32(idLen);

        if ($.operatorApprovals[address(this)][msgSender].value != 0) {
            if (lock) $.numExchangableNFT -= uint32(ids.length);
            else $.numExchangableNFT += uint32(ids.length);
        }
    }

    /// @dev Returns the NFT IDs of `owner` in range `[begin, end)`.
    /// Optimized for smaller bytecode size, as this function is intended for off-chain calling.
    function _ownedIds(address owner, uint256 begin, uint256 end, bool locked)
        internal
        view
        virtual
        returns (uint256[] memory ids)
    {
        DN404Storage storage $ = _getDN404Storage();
        (Uint32Map storage owned, uint256 n) = locked
            ? ($.locked[owner], $.addressData[owner].lockedLength)
            : ($.owned[owner], $.addressData[owner].ownedLength);
        n = _min(n, end);
        /// @solidity memory-safe-assembly
        assembly {
            // Allocate one more word to store the offset when returning with assembly.
            ids := mload(0x40)
            mstore(0x20, owned.slot)
            let i := begin
            for {} lt(i, n) { i := add(i, 1) } {
                mstore(0x00, shr(3, i))
                let s := keccak256(0x00, 0x40) // Storage slot.
                let id := and(0xffffffff, shr(shl(5, and(i, 7)), sload(s)))
                mstore(add(add(ids, 0x20), shl(5, sub(i, begin))), id) // Append to.
            }
            mstore(ids, sub(i, begin)) // Store the length.
            mstore(0x40, add(add(ids, 0x20), shl(5, sub(i, begin)))) // Allocate memory.
        }
    }

    /// @dev Fallback modifier to dispatch calls from the mirror NFT contract
    /// to internal functions in this contract.
    modifier dn404Fallback() virtual {
        DN404Storage storage $ = _getDN404Storage();

        uint256 fnSelector = _calldataload(0x00) >> 224;
        address mirror = $.mirrorERC721;

        // `transferFromNFT(address,address,uint256,address)`.
        if (fnSelector == 0xe5eb36c8) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            _transferFromNFT(
                address(uint160(_calldataload(0x04))), // `from`.
                address(uint160(_calldataload(0x24))), // `to`.
                _calldataload(0x44), // `id`.
                address(uint160(_calldataload(0x64))) // `msgSender`.
            );
            _return(1);
        }
        // `setApprovalForAll(address,bool,address)`.
        if (fnSelector == 0x813500fc) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            _setApprovalForAll(
                address(uint160(_calldataload(0x04))), // `spender`.
                _calldataload(0x24) != 0, // `status`.
                address(uint160(_calldataload(0x44))) // `msgSender`.
            );
            _return(1);
        }
        // `exchangeNFT(uint256,uint256,address)`.
        if (fnSelector == 0x2c5966af) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            (address x, address y, uint256 fee) = _exchangeNFT(
                _calldataload(0x04), // `idX`
                _calldataload(0x24), // `idY`
                address(uint160(_calldataload(0x44))) // `msgSender`
            );

            /// @solidity memory-safe-assembly
            assembly {
                mstore(0x00, x)
                mstore(0x20, y)
                mstore(0x40, fee)
                return(0x00, 0x60)
            }
        }
        // `setNFTLockState(uint256,uint256[])`.
        if (fnSelector == 0xb79cc1bd) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();

            uint256 senderAndLockFlag = _calldataload(0x04);
            uint256[] memory ids;
            assembly {
                let offset := add(0x24, calldataload(0x24))
                let length := calldataload(sub(offset, 0x20))
                ids := mload(0x40)
                mstore(0x40, add(add(ids, 0x20), shl(5, length))) // Allocate memory.

                mstore(ids, length) // Store array length
                calldatacopy(add(ids, 0x20), offset, shl(5, length)) // Copy array elements
            }

            _setNFTLockState(
                ids, // `ids`
                uint8(senderAndLockFlag) != 0, // `lock`
                address(uint160(senderAndLockFlag >> 96)) // `msgSender`
            );
            _return(1);
        }
        // `isApprovedForAll(address,address)`.
        if (fnSelector == 0xe985e9c5) {
            address owner = address(uint160(_calldataload(0x04)));
            address spender = address(uint160(_calldataload(0x24)));
            Uint256Ref storage ref = $.operatorApprovals[spender][owner];

            _return(ref.value);
        }
        // `ownerOf(uint256)`.
        if (fnSelector == 0x6352211e) {
            _return(uint160(_ownerOf(_calldataload(0x04))));
        }
        // `ownerAt(uint256)`.
        if (fnSelector == 0x24359879) {
            _return(uint160(_ownerAt(_calldataload(0x04))));
        }
        // `approveNFT(address,uint256,address)`.
        if (fnSelector == 0xd10b6e0c) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            address owner = _approveNFT(
                address(uint160(_calldataload(0x04))), // `spender`.
                _calldataload(0x24), // `id`.
                address(uint160(_calldataload(0x44))) // `msgSender`.
            );
            _return(uint160(owner));
        }
        // `ownedIds(uint256,uint256,uint256)`.
        if (fnSelector == 0xf9b4b328) {
            uint256 addrAndFlag = _calldataload(0x04);
            /// @solidity memory-safe-assembly
            assembly {
                // Allocate one word to store the offset of the array in returndata.
                mstore(0x40, add(mload(0x40), 0x20))
            }

            uint256[] memory ids = _ownedIds(
                address(uint160(addrAndFlag >> 96)),
                _calldataload(0x24),
                _calldataload(0x44),
                uint8(addrAndFlag) != 0
            );
            /// @solidity memory-safe-assembly
            assembly {
                // Memory safe, as we've advanced the free memory pointer by a word.
                let p := sub(ids, 0x20)
                mstore(p, 0x20) // Store the offset of the array in returndata.
                return(p, add(0x40, shl(5, mload(ids))))
            }
        }
        // `getApproved(uint256)`.
        if (fnSelector == 0x081812fc) {
            _return(uint160(_getApproved(_calldataload(0x04))));
        }
        // `balanceOfNFT(address)`.
        if (fnSelector == 0xf5b100ea) {
            _return(_balanceOfNFT(address(uint160(_calldataload(0x04)))));
        }
        // `totalNFTSupply()`.
        if (fnSelector == 0xe2c79281) {
            _return(_totalNFTSupply());
        }
        // `implementsDN404()`.
        if (fnSelector == 0xb7a94eb8) {
            _return(1);
        }
        _;
    }

    /// @dev Fallback function for calls from mirror NFT contract.
    fallback() external payable virtual dn404Fallback {}

    receive() external payable virtual {}

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 INTERNAL / PRIVATE HELPERS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns `(i - 1) << 1`.
    function _ownershipIndex(uint256 i) internal pure returns (uint256) {
        unchecked {
            return (i - 1) << 1; // Minus 1 as token IDs start from 1.
        }
    }

    /// @dev Returns `((i - 1) << 1) + 1`.
    function _ownedIndex(uint256 i) internal pure returns (uint256) {
        unchecked {
            return ((i - 1) << 1) + 1; // Minus 1 as token IDs start from 1.
        }
    }

    /// @dev Wraps the NFT ID.
    /// @dev Returns `id > maxId ? 1 : id`
    function _wrapNFTId(uint256 id, uint256 maxId) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(mul(iszero(gt(id, maxId)), id), gt(id, maxId))
        }
    }

    function _delNFTAt(
        Uint32Map storage owned,
        Uint32Map storage oo,
        uint256 toDelIndex,
        uint256 lastIndex
    ) internal {
        if (toDelIndex != lastIndex) {
            uint256 updatedId = _get(owned, lastIndex);
            _set(owned, toDelIndex, uint32(updatedId));
            _set(oo, _ownedIndex(updatedId), uint32(toDelIndex));
        }
    }

    /// @dev Returns whether `amount` is a valid `totalSupply`.
    function _totalSupplyOverflows(uint256 amount) internal view returns (bool result) {
        uint256 unit = _unit();
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(or(shr(96, amount), lt(0xfffffffe, div(amount, unit)))))
        }
    }

    /// @dev Struct containing direct transfer log data for {Transfer} events to be
    /// emitted by the mirror NFT contract.
    struct _DNDirectLogs {
        uint256 offset;
        address from;
        address to;
        uint256[] logs;
    }

    /// @dev Initiates memory allocation for direct logs with `n` log items.
    function _directLogsMalloc(uint256 n, address from, address to)
        private
        pure
        returns (_DNDirectLogs memory p)
    {
        /// @solidity memory-safe-assembly
        assembly {
            // Note that `p` implicitly allocates and advances the free memory pointer by
            // 4 words, which we can safely mutate in `_packedLogsSend`.
            let logs := mload(0x40)
            mstore(logs, n) // Store the length.
            let offset := add(0x20, logs) // Skip the word for `p.logs.length`.
            mstore(0x40, add(offset, shl(5, n))) // Allocate memory.
            mstore(add(0x60, p), logs) // Set `p.logs`.
            mstore(add(0x40, p), shr(96, shl(96, to))) // Set `p.to`.
            mstore(add(0x20, p), shr(96, shl(96, from))) // Set `p.from`.
            mstore(p, offset) // Set `p.offset`.
        }
    }

    /// @dev Adds a direct log item to `p` with token `id`.
    function _directLogsAppend(_DNDirectLogs memory p, uint256 id) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            let offset := mload(p)
            mstore(offset, id)
            mstore(p, add(offset, 0x20))
        }
    }

    /// @dev Calls the `mirror` NFT contract to emit {Transfer} events for packed logs `p`.
    function _directLogsSend(_DNDirectLogs memory p, address mirror) private {
        /// @solidity memory-safe-assembly
        assembly {
            let logs := mload(add(p, 0x60))
            let n := add(0x84, shl(5, mload(logs))) // Length of calldata to send.
            let o := sub(logs, 0x80) // Start of calldata to send.
            mstore(o, 0x144027d3) // `logDirectTransfer(address,address,uint256[])`.
            mstore(add(o, 0x20), mload(add(0x20, p)))
            mstore(add(o, 0x40), mload(add(0x40, p)))
            mstore(add(o, 0x60), 0x60) // Offset of `logs` in the calldata to send.
            if iszero(and(eq(mload(o), 1), call(gas(), mirror, 0, add(o, 0x1c), n, o, 0x20))) {
                revert(o, 0x00)
            }
        }
    }

    /// emitted by the mirror NFT contract.
    struct _PackedLogs {
        uint256 offset;
        uint256 addressAndBit;
        uint256[] logs;
    }

    /// @dev Initiates memory allocation for packed logs with `n` log items.
    function _packedLogsMalloc(uint256 n) internal pure returns (_PackedLogs memory p) {
        /// @solidity memory-safe-assembly
        assembly {
            // Note that `p` implicitly allocates and advances the free memory pointer by
            // 2 words, which we can safely mutate in `_packedLogsSend`.
            let logs := mload(0x40)
            mstore(logs, n) // Store the length.
            let offset := add(0x20, logs)
            mstore(0x40, add(offset, shl(5, n))) // Allocate memory.
            mstore(add(0x40, p), logs) // Set `p.logs`.
            mstore(p, offset) // Set `p.offset`.
        }
    }

    /// @dev Set the current address and the burn bit.
    function _packedLogsSet(_PackedLogs memory p, address a, uint256 burnBit) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(add(p, 0x20), or(shl(96, a), burnBit))
        }
    }

    /// @dev Adds a packed log item to `p` with token `id`.
    function _packedLogsAppend(_PackedLogs memory p, uint256 id) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            let offset := mload(p)
            mstore(offset, or(mload(add(p, 0x20)), shl(8, id)))
            mstore(p, add(offset, 0x20))
        }
    }

    function _packedLogsSend(_PackedLogs memory p, address mirror) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let logs := mload(add(p, 0x40))
            let o := sub(logs, 0x40) // Start of calldata to send.
            mstore(o, 0x263c69d6) // `logTransfer(uint256[])`.
            mstore(add(o, 0x20), 0x20) // Offset of `logs` in the calldata to send.
            let n := add(0x44, shl(5, mload(logs))) // Length of calldata to send.
            if iszero(and(eq(mload(o), 1), call(gas(), mirror, 0, add(o, 0x1c), n, o, 0x20))) {
                revert(o, 0x00)
            }
        }
    }

    /// @dev Struct of temporary variables for transfers.
    struct _TransferTemps {
        uint256 numNFTBurns;
        uint256 numNFTMints;
        uint256 fromBalance;
        uint256 toBalance;
        uint256 fromOwnedLength;
        uint256 toOwnedLength;
        uint256 totalSupply;
        uint256 fromLockedLength;
        uint256 toLockedLength;
    }

    /// @dev Returns if `a` has bytecode of non-zero length.
    function _hasCode(address a) private view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := extcodesize(a) // Can handle dirty upper bits.
        }
    }

    /// @dev Returns the calldata value at `offset`.
    function _calldataload(uint256 offset) private pure returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := calldataload(offset)
        }
    }

    /// @dev Executes a return opcode to return `x` and end the current call frame.
    function _return(uint256 x) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, x)
            return(0x00, 0x20)
        }
    }

    /// @dev Returns `max(0, x - y)`.
    function _zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    /// @dev Returns `x < y ? x : y`.
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }

    /// @dev Returns `b ? 1 : 0`.
    function _toUint(bool b) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(b))
        }
    }

    /// @dev Returns the uint32 value at `index` in `map`.
    function _get(Uint32Map storage map, uint256 index) internal view returns (uint32 result) {
        result = uint32(map.map[index >> 3] >> ((index & 7) << 5));
    }

    /// @dev Updates the uint32 value at `index` in `map`.
    function _set(Uint32Map storage map, uint256 index, uint32 value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, map.slot)
            mstore(0x00, shr(3, index))
            let s := keccak256(0x00, 0x40) // Storage slot.
            let o := shl(5, and(index, 7)) // Storage slot offset (bits).
            let v := sload(s) // Storage slot value.
            let m := 0xffffffff // Value mask.
            sstore(s, xor(v, shl(o, and(m, xor(shr(o, v), value)))))
        }
    }

    /// @dev Sets the owner alias and the owned index together.
    function _setOwnerAliasAndOwnedIndex(
        Uint32Map storage map,
        uint256 id,
        uint32 ownership,
        uint32 ownedIndex
    ) internal {
        /// @solidity memory-safe-assembly
        assembly {
            id := sub(id, 1) // minus as index starts from 0
            let value := or(shl(32, ownedIndex), and(0xffffffff, ownership))
            mstore(0x20, map.slot)
            mstore(0x00, shr(2, id))
            let s := keccak256(0x00, 0x40) // Storage slot.
            let o := shl(6, and(id, 3)) // Storage slot offset (bits).
            let v := sload(s) // Storage slot value.
            let m := 0xffffffffffffffff // Value mask.
            sstore(s, xor(v, shl(o, and(m, xor(shr(o, v), value)))))
        }
    }
}
