// SPDX-License-Identifier: MIT

pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

interface DeployerInterface {
  function signer(address) external view returns (bool); 
  function isConnector(address[] calldata) external view returns (bool);
}

contract Flusher {
  event LogCast(address indexed sender, uint value);

  string constant public name = "Flusher-v1";

  DeployerInterface public constant deployer = DeployerInterface(address(0)); // TODO - Change while deploying

  function spell(address _target, bytes memory _data) internal {
    require(_target != address(0), "target-invalid");
    assembly {
      let succeeded := delegatecall(gas(), _target, add(_data, 0x20), mload(_data), 0, 0)
      switch iszero(succeeded)
        case 1 {
            let size := returndatasize()
            returndatacopy(0x00, 0x00, size)
            revert(0x00, size)
        }
    }
  }

  function cast(address[] calldata _targets, bytes[] calldata _datas) external payable {
    require(deployer.signer(msg.sender), "not-signer");
    require(_targets.length == _datas.length , "invalid-array-length");
    require(deployer.isConnector(_targets), "not-connector");
    for (uint i = 0; i < _targets.length; i++) {
        spell(_targets[i], _datas[i]);
    }
    emit LogCast(msg.sender, msg.value);
  }

  receive() external payable {}
}