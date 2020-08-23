// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { DSMath } from "./../libs/safeMath.sol";

// TODO - Add ReentrancyGuard lib

interface AccountInterface {
  function enable(address authority) external;
  function cast(address[] calldata _targets, bytes[] calldata _datas, address _origin) external payable;
}

interface IndexInterface {
  function master() external view returns (address);
  function build(address _owner, uint accountVersion, address _origin) external returns (address _account);
}

interface RegistryInterface {
  function chief(address) external view returns (bool);
  function poolLogic(address) external returns (address);
  function poolCap(address) external view returns (uint);
  function insureFee(address) external view returns (uint);
}

interface RateInterface {
  function totalBalance() external view returns (uint);
  function getTotalToken() external returns (uint totalUnderlyingTkn);
}

contract PoolToken is ERC20, DSMath {
    using SafeERC20 for IERC20;

    IERC20 public immutable baseToken;
    RegistryInterface public immutable registry;
    IndexInterface public constant instaIndex = IndexInterface(0x2971AdFa57b20E5a416aE5a708A8655A9c74f723);
    AccountInterface public immutable dsa;

    uint private tokenBalance; // total token balance since last rebalancing
    uint public exchangeRate = 1000000000000000000; // initial 1 token = 1
    uint public insuranceAmt; // insurance amount to keep pool safe
    bool public shutPool;

    constructor(
        address _registry,
        string memory _name,
        string memory _symbol,
        address _baseToken,
        address _origin
    ) public ERC20(_name, _symbol) {
        // TODO - 0
        baseToken = IERC20(_baseToken);
        registry = RegistryInterface(_registry);
        address _dsa = instaIndex.build(address(this), 1, _origin);
        dsa = AccountInterface(_dsa);
    }

    modifier isChief() {
        require(registry.chief(msg.sender) || msg.sender == instaIndex.master(), "not-chief");
        _;
    }

    function deploy(uint amount) public isChief {
        baseToken.safeTransfer(address(dsa), amount);
    }

    function setExchangeRate() public isChief {
        uint _previousRate = exchangeRate;
        uint _totalToken = RateInterface(registry.poolLogic(address(this))).getTotalToken();
        uint _currentRate = wdiv(_totalToken, totalSupply());
        if (_currentRate < _previousRate) {
            uint difRate = _previousRate - _currentRate;
            uint difTkn = wmul(_totalToken, difRate);
            insuranceAmt = sub(insuranceAmt, difTkn);
            _currentRate = _previousRate;
        } else {
            uint difRate = _currentRate - _previousRate;
            uint insureFee = wmul(difRate, registry.insureFee(address(this))); // 1e17
            uint insureFeeAmt = wmul(_totalToken, insureFee);
            insuranceAmt = add(insuranceAmt, insureFeeAmt);
            _currentRate = sub(_currentRate, insureFee);
            tokenBalance = sub(_totalToken, insuranceAmt);
        }
        exchangeRate = _currentRate;
    }

    function settle(address[] calldata _targets, bytes[] calldata _datas, address _origin) external isChief {
        if (_targets.length > 0 && _datas.length > 0) {
            dsa.cast(_targets, _datas, _origin);
        }
        setExchangeRate();
    }

    function deposit(uint tknAmt) external payable returns(uint) {
        require(!shutPool, "pool-shut");
        uint _newTokenBal = add(tokenBalance, tknAmt);
        require(_newTokenBal <= registry.poolCap(address(this)), "deposit-cap-reached");

        baseToken.safeTransferFrom(msg.sender, address(this), tknAmt);
        uint _mintAmt = wdiv(tknAmt, exchangeRate);
        _mint(msg.sender, _mintAmt);
    }

    function withdraw(uint tknAmt, address to) external returns (uint) {
        require(!shutPool, "pool-shut");
        uint poolBal = baseToken.balanceOf(address(this));
        require(tknAmt <= poolBal, "not-enough-liquidity-available");
        uint _bal = balanceOf(msg.sender);
        uint _tknBal = wmul(_bal, exchangeRate);
        uint _burnAmt;
        uint _tknAmt;
        if (tknAmt == uint(-1)) {
            _burnAmt = _bal;
            _tknAmt = wmul(_burnAmt, exchangeRate);
        } else {
            require(tknAmt <= _tknBal, "balance-exceeded");
            _burnAmt = wdiv(tknAmt, exchangeRate);
            _tknAmt = tknAmt;
        }

        _burn(msg.sender, _burnAmt);

        baseToken.safeTransfer(to, _tknAmt);
    }

    function addInsurance(uint tknAmt) external {
        baseToken.safeTransferFrom(msg.sender, address(this), tknAmt);
        insuranceAmt = tknAmt;
    }

    function shutdown() external {
        require(msg.sender == instaIndex.master(), "not-master");
        shutPool = !shutPool;
    }

}
