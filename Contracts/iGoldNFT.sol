// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IiGoldToken {}

contract iGoldNFT is ERC721, Ownable {
    using Counters for Counters.Counter;

    IiGoldToken public iGoldToken;

    Counters.Counter private _tokenIdCounter;

    string private _baseTokenURI;

    uint256 private _totalSupply;

    mapping(uint256 => string) private _tokenURIs;


    event MintershipTransferred(
        address indexed previousMinter,
        address indexed newMinter
    );

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) ERC721(name, symbol) {
        _baseTokenURI = baseTokenURI;
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

    function mint(address to) public returns (uint256 _tokenId) {
        require(
            msg.sender == address(iGoldToken),
            "iGoldNFT: only iGold contract can mint tokens"
        );
        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        _mint(to, newTokenId);
        _totalSupply++;
        string memory newTokenURI = string(abi.encodePacked(_baseTokenURI, newTokenId, ".json"));
        _setTokenURI(newTokenId, newTokenURI);
        return (newTokenId);
    }

    function burn(address _ownerOf, uint256 tokenId) public {
        require(
            msg.sender == address(iGoldToken),
            "iGoldNFT: only iGold contract can burn tokens"
        );
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
