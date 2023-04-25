// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IiGoldToken {}

contract iGoldNFT is ERC721, Ownable {
    using Counters for Counters.Counter;

    IiGoldToken public iGoldToken;

    address public iGoldDex;

    Counters.Counter private _tokenIdCounter;

    string private _baseTokenURI;

    uint256 private _totalSupply;

    mapping(uint256 => string) private _tokenURIs;
    mapping(address => bool) public minters;
    mapping(uint256 => address) public tag;

    modifier onlyMinter() {
        require(minters[msg.sender], "Caller is not minter");
        _;
    }
    

    event MintershipTransferred(
        address indexed previousMinter,
        address indexed newMinter
    );

    constructor(string memory baseTokenURI) ERC721("iGoldNFT", "iGoldNFT") {
        _baseTokenURI = baseTokenURI;
    }

    function addMinter(address _minter) external{
        require(msg.sender == iGoldDex, "only factory can add minters");
        require(_minter != address(0x0), "address zero!");
        minters[_minter] = true;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function setIGoldToken(address _iGold) external onlyOwner {
        require(_iGold != address(0x0), "iGoldNFT: zero address!");
        iGoldToken = IiGoldToken(_iGold);
    }

    function setBaseTokenURI(string memory baseTokenURI) public onlyOwner {
        _baseTokenURI = baseTokenURI;
    }

    function mint(address to) public onlyMinter returns (uint256 _tokenId) {
        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        _mint(to, newTokenId);
        _totalSupply++;
        string memory tokenIdString = Strings.toString(newTokenId);
        string memory newTokenURI = string(
            abi.encodePacked(_baseTokenURI, tokenIdString, ".json")
        );
        _setTokenURI(newTokenId, newTokenURI);
        tag[newTokenId] = msg.sender;
        return (newTokenId);
    }

    function burn(address _ownerOf, uint256 tokenId) public onlyMinter{
        require(_exists(tokenId), "iGoldNFT: burn of nonexistent token");
        require(
            ownerOf(tokenId) == _ownerOf,
            "iGoldNFT: caller is not the owner of the token"
        );
        _totalSupply--;
        _burn(tokenId);
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI)
        internal
        virtual
    {
        require(_exists(tokenId), "iGoldNFT: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "iGoldNFT: URI query for nonexistent token");
        string memory _tokenURI = _tokenURIs[tokenId];
        return
            bytes(_tokenURI).length > 0
                ? _tokenURI
                : string(abi.encodePacked(_baseTokenURI, tokenId));
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

                /*********************************************************
                    Proudly Developed by MetaIdentity ltd. Copyright 2023
                **********************************************************/
