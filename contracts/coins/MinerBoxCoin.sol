// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./generation/CoinGenerator.sol";
import "../util/ownership/ProjectOwnable.sol";

contract MinerBoxCoin is ERC20, ProjectOwnable {
    CoinGenerator private coinGenerator;
    uint256 private amountLeftForGeneration;
    uint256 private totalAllowedSupply;

    // A modifier to prevent any caller except from the shop to call a method
    modifier onlyGenerator() {
        require(
            address(coinGenerator) == _msgSender(),
            "NFT: Caller ist not the Generator"
        );
        _;
    }

    constructor(
        ProjectOwnership _ownership,
        string memory name,
        string memory symbol,
        address[] memory preMintAddresses,
        uint256[] memory preMintBalances,
        uint256 _amountLeftForGeneration,
        NFTStaking _staker,
        uint256 _generationRatePerDay,
        ERC20 _refuelingToken,
        address _refuelingTreasury
    ) ERC20(name, symbol) ProjectOwnable(_ownership) {
        coinGenerator = new CoinGenerator(
            _ownership,
            this,
            _staker,
            _generationRatePerDay,
            _refuelingToken,
            _refuelingTreasury
        );

        require(
            preMintAddresses.length == preMintBalances.length,
            "Arrays must have same size."
        );

        for (uint256 i = 0; i < preMintAddresses.length; i++) {
            _mint(preMintAddresses[i], preMintBalances[i]);
            totalAllowedSupply += preMintBalances[i];
        }

        amountLeftForGeneration = _amountLeftForGeneration;
        totalAllowedSupply += _amountLeftForGeneration;
    }

    function mint(address to, uint256 amount) public onlyGenerator {
        require(
            getCurrentSupply() + amount <= totalAllowedSupply,
            "All tokens were minted"
        );
        _mint(to, amount);
    }

    function setGenerator(CoinGenerator _coinGenerator) external onlyProject {
        coinGenerator = _coinGenerator;
    }

    function getGenerator() external view returns (CoinGenerator) {
        return coinGenerator;
    }

    function getCurrentSupply() public view returns (uint256) {
        return totalSupply();
    }

    function getTotalAllowedSupply() public view returns (uint256) {
        return totalAllowedSupply;
    }
}
