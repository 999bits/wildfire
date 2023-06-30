// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155} from "./CustomERC1155/ERC1155.sol";
import {ERC1155Supply} from "./CustomERC1155/ERC1155Supply.sol";

contract VaultToken is ERC1155 {
    string public name;
    string public symbol;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri
    ) ERC1155(_uri) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, "");
    }
}
