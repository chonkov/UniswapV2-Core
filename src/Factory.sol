// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable2Step, Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {Pair} from "./Pair.sol";

error Factory_Identical_Addresses();
error Factory_Zero_Address();
error Factory_Pair_Already_Exists();

contract Factory is IFactory, Ownable2Step {
    address private _feeTo;

    mapping(address => mapping(address => address)) private _pairs;
    address[] private _allPairs;

    constructor(address _owner) Ownable(_owner) {}

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert Factory_Identical_Addresses();
        if (tokenA == address(0)) revert Factory_Zero_Address();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (_pairs[token0][token1] != address(0)) revert Factory_Pair_Already_Exists();
        bytes memory bytecode = type(Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        Pair(pair).initialize(token0, token1);
        _pairs[token0][token1] = pair;
        _pairs[token1][token0] = pair;
        _allPairs.push(pair);
        emit PairCreated(token0, token1, pair, _allPairs.length);
    }

    function setFeeTo(address feeTo_) external onlyOwner {
        _feeTo = feeTo_;
    }

    function feeTo() external view returns (address) {
        return _feeTo;
    }

    function allPairsLength() external view returns (uint256) {
        return _allPairs.length;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return _pairs[tokenA][tokenB];
    }

    function allPairs(uint256 _index) external view returns (address) {
        return _allPairs[_index];
    }
}
