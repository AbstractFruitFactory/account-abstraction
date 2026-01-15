// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {PolicyManager} from "./PolicyManager.sol";
import {SessionKeyManager} from "./SessionKeyManager.sol";
import {UserOperation, IEntryPoint, Call} from "./Types.sol";

contract SmartAccount {
	using ECDSA for bytes32;
	using MessageHashUtils for bytes32;

	error NotEntryPoint();
	error InvalidSignature();
	error PolicyRejected();
	error InvalidBatch();

	address public owner;
	IEntryPoint public immutable entryPoint;
	PolicyManager public policyManager;
	SessionKeyManager public sessionKeyManager;

	event OwnerChanged(address indexed oldOwner, address indexed newOwner);
	event PolicyManagerChanged(address indexed oldManager, address indexed newManager);
	event SessionKeyManagerChanged(address indexed oldManager, address indexed newManager);
	event Executed(address indexed target, uint256 value, bytes4 selector, bool success);
	event BatchExecuted(uint256 count);

	constructor(
		address _owner,
		IEntryPoint _entryPoint,
		PolicyManager _policyManager,
		SessionKeyManager _sessionKeyManager
	) {
		owner = _owner;
		entryPoint = _entryPoint;
		policyManager = _policyManager;
		sessionKeyManager = _sessionKeyManager;
	}

	receive() external payable {}

	function validateUserOp(
		UserOperation calldata userOp,
		bytes32 userOpHash,
		uint256 missingAccountFunds
	) external returns (uint256 validationData) {
		if (msg.sender != address(entryPoint)) revert NotEntryPoint();

		bool validOwner = _isValidOwnerSig(userOpHash, userOp.signature);
		bytes4 selector = _selector(userOp.callData);
		bool isAdmin = _isAdminSelector(selector);
		(Call[] memory calls, uint256 totalValue, bool ok) = _decodeCalls(userOp.callData);
		if (!isAdmin && !ok) revert PolicyRejected();

		if (!validOwner) {
			if (isAdmin) return 1;
			(bool sessionOk, ) = sessionKeyManager.isSessionKeyValid(
				address(this),
				userOpHash,
				userOp.signature,
				calls,
				totalValue
			);
			if (!sessionOk) return 1;
		}

		if (!isAdmin) {
			(bool policyOk, ) = policyManager.validateCall(address(this), calls);
			if (!policyOk) revert PolicyRejected();
		}

		if (missingAccountFunds > 0) {
			(bool okPrefund, ) = payable(address(entryPoint)).call{value: missingAccountFunds}('');
			okPrefund;
		}

		return 0;
	}

	function execute(address target, uint256 value, bytes calldata data) external {
		if (msg.sender != address(entryPoint)) revert NotEntryPoint();
		(bool ok, bytes memory ret) = target.call{value: value}(data);
		if (!ok) {
			assembly {
				revert(add(ret, 32), mload(ret))
			}
		}
		Call[] memory calls = new Call[](1);
		calls[0] = Call({target: target, value: value, data: data});
		policyManager.postExec(address(this), calls);
		emit Executed(target, value, _selector(data), true);
	}

	function executeBatch(
		address[] calldata targets,
		uint256[] calldata values,
		bytes[] calldata datas
	) external {
		if (msg.sender != address(entryPoint)) revert NotEntryPoint();
		if (targets.length != values.length || targets.length != datas.length) revert InvalidBatch();
		for (uint256 i = 0; i < targets.length; i++) {
			(bool ok, bytes memory ret) = targets[i].call{value: values[i]}(datas[i]);
			if (!ok) {
				assembly {
					revert(add(ret, 32), mload(ret))
				}
			}
			emit Executed(targets[i], values[i], _selector(datas[i]), true);
		}
		Call[] memory calls = new Call[](targets.length);
		for (uint256 i = 0; i < targets.length; i++) {
			calls[i] = Call({target: targets[i], value: values[i], data: datas[i]});
		}
		policyManager.postExec(address(this), calls);
		emit BatchExecuted(targets.length);
	}

	function setPolicyManager(address newManager) external {
		if (msg.sender != address(entryPoint)) revert NotEntryPoint();
		address old = address(policyManager);
		policyManager = PolicyManager(newManager);
		emit PolicyManagerChanged(old, newManager);
	}

	function setSessionKeyManager(address newManager) external {
		if (msg.sender != address(entryPoint)) revert NotEntryPoint();
		address old = address(sessionKeyManager);
		sessionKeyManager = SessionKeyManager(newManager);
		emit SessionKeyManagerChanged(old, newManager);
	}

	function transferOwnership(address newOwner) external {
		if (msg.sender != address(entryPoint)) revert NotEntryPoint();
		address old = owner;
		owner = newOwner;
		emit OwnerChanged(old, newOwner);
	}

	function _isValidOwnerSig(bytes32 userOpHash, bytes calldata sig) internal view returns (bool) {
		bytes32 digest = userOpHash.toEthSignedMessageHash();
		address recovered = digest.recover(sig);
		return recovered == owner;
	}

	function _decodeCalls(
		bytes calldata callData
	) internal pure returns (Call[] memory calls, uint256 totalValue, bool ok) {
		if (callData.length < 4) return (calls, 0, false);
		bytes4 selector = _selector(callData);
		if (selector == bytes4(keccak256("execute(address,uint256,bytes)"))) {
			(address target, uint256 value, bytes memory data) = abi.decode(
				callData[4:],
				(address, uint256, bytes)
			);
			calls = new Call[](1);
			calls[0] = Call({target: target, value: value, data: data});
			return (calls, value, true);
		}
		if (selector == bytes4(keccak256("executeBatch(address[],uint256[],bytes[])"))) {
			(address[] memory targets, uint256[] memory values, bytes[] memory datas) = abi.decode(
				callData[4:],
				(address[], uint256[], bytes[])
			);
			if (targets.length != values.length || targets.length != datas.length) return (calls, 0, false);
			calls = new Call[](targets.length);
			for (uint256 i = 0; i < targets.length; i++) {
				calls[i] = Call({target: targets[i], value: values[i], data: datas[i]});
				totalValue += values[i];
			}
			return (calls, totalValue, true);
		}
		return (calls, 0, false);
	}

	function _isAdminSelector(bytes4 selector) internal pure returns (bool) {
		return
			selector == bytes4(keccak256("setPolicyManager(address)")) ||
			selector == bytes4(keccak256("setSessionKeyManager(address)")) ||
			selector == bytes4(keccak256("transferOwnership(address)"));
	}

	function _selector(bytes calldata data) internal pure returns (bytes4) {
		if (data.length < 4) return bytes4(0);
		return bytes4(data[:4]);
	}
}
