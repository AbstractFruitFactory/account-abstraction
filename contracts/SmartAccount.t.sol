// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SmartAccount} from "./SmartAccount.sol";
import {PolicyManager} from "./PolicyManager.sol";
import {SessionKeyManager} from "./SessionKeyManager.sol";
import {UserOperation, IEntryPoint} from "./Types.sol";
import {Counter} from "./Counter.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MockEntryPoint is IEntryPoint {
	function getUserOpHash(UserOperation calldata userOp) external pure returns (bytes32) {
		return keccak256(
			abi.encode(
				userOp.sender,
				userOp.nonce,
				userOp.initCode,
				userOp.callData,
				userOp.callGasLimit,
				userOp.verificationGasLimit,
				userOp.preVerificationGas,
				userOp.maxFeePerGas,
				userOp.maxPriorityFeePerGas,
				userOp.paymasterAndData
			)
		);
	}

	function depositTo(address) external payable {}
}

contract Reverter {
	function boom() external pure {
		revert("boom");
	}
}

contract SmartAccountTest is Test {
	using MessageHashUtils for bytes32;

	uint256 ownerKey;
	address owner;
	MockEntryPoint entryPoint;
	SmartAccount account;
	PolicyManager policyManager;
	SessionKeyManager sessionKeyManager;
	Counter counter;
	Reverter reverter;

	function setUp() public {
		ownerKey = 0xA11CE;
		owner = vm.addr(ownerKey);
		entryPoint = new MockEntryPoint();
		policyManager = new PolicyManager();
		sessionKeyManager = new SessionKeyManager();
		account = new SmartAccount(owner, entryPoint, policyManager, sessionKeyManager);
		counter = new Counter();
		reverter = new Reverter();
	}

	function test_ValidSignatureExecute() public {
		bytes memory targetCallData = abi.encodeWithSignature("inc()");
		bytes memory accountCallData = abi.encodeWithSignature(
			"execute(address,uint256,bytes)",
			address(counter),
			0,
			targetCallData
		);
		UserOperation memory userOp = _buildUserOp(accountCallData);
		bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
		bytes32 digest = userOpHash.toEthSignedMessageHash();
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
		userOp.signature = abi.encodePacked(r, s, v);

		vm.prank(address(entryPoint));
		uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);
		assertEq(validationData, 0);

		vm.prank(address(entryPoint));
		account.execute(address(counter), 0, targetCallData);
		assertEq(counter.x(), 1);
	}

	function test_InvalidSignatureFailsValidation() public {
		bytes memory targetCallData = abi.encodeWithSignature("inc()");
		bytes memory accountCallData = abi.encodeWithSignature(
			"execute(address,uint256,bytes)",
			address(counter),
			0,
			targetCallData
		);
		UserOperation memory userOp = _buildUserOp(accountCallData);
		bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
		bytes32 digest = userOpHash.toEthSignedMessageHash();
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(0xB0B, digest);
		userOp.signature = abi.encodePacked(r, s, v);

		vm.prank(address(entryPoint));
		uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);
		assertEq(validationData, 1);
	}

	function test_SessionKeySignatureExecute() public {
		uint256 sessionKey = 0xB0B0B0;
		address sessionKeyAddr = vm.addr(sessionKey);
		address[] memory targets = new address[](1);
		targets[0] = address(counter);
		bytes4[][] memory selectors = new bytes4[][](1);
		selectors[0] = new bytes4[](1);
		selectors[0][0] = bytes4(keccak256("inc()"));
		SessionKeyManager.SessionConfig memory cfg = SessionKeyManager.SessionConfig({
			validAfter: 0,
			validUntil: uint64(block.timestamp + 1 days),
			maxValuePerTx: 0,
			targetAllowlistEnabled: true,
			selectorAllowlistEnabled: true
		});
		bytes memory setKeyCall = abi.encodeWithSelector(
			SessionKeyManager.createSessionKey.selector,
			sessionKeyAddr,
			cfg,
			targets,
			selectors
		);

		vm.prank(address(entryPoint));
		account.execute(address(sessionKeyManager), 0, setKeyCall);

		bytes memory targetCallData = abi.encodeWithSignature("inc()");
		bytes memory accountCallData = abi.encodeWithSignature(
			"execute(address,uint256,bytes)",
			address(counter),
			0,
			targetCallData
		);
		UserOperation memory userOp = _buildUserOp(accountCallData);
		bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
		bytes32 digest = userOpHash.toEthSignedMessageHash();
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKey, digest);
		userOp.signature = abi.encodePacked(r, s, v);

		vm.prank(address(entryPoint));
		uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);
		assertEq(validationData, 0);

		vm.prank(address(entryPoint));
		account.execute(address(counter), 0, targetCallData);
		assertEq(counter.x(), 1);
	}

	function test_ValidateUserOpOnlyEntryPoint() public {
		bytes memory targetCallData = abi.encodeWithSignature("inc()");
		bytes memory accountCallData = abi.encodeWithSignature(
			"execute(address,uint256,bytes)",
			address(counter),
			0,
			targetCallData
		);
		UserOperation memory userOp = _buildUserOp(accountCallData);
		bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
		bytes32 digest = userOpHash.toEthSignedMessageHash();
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
		userOp.signature = abi.encodePacked(r, s, v);

		vm.expectRevert(SmartAccount.NotEntryPoint.selector);
		account.validateUserOp(userOp, userOpHash, 0);
	}

	function test_ExecuteOnlyEntryPoint() public {
		bytes memory targetCallData = abi.encodeWithSignature("inc()");
		vm.expectRevert(SmartAccount.NotEntryPoint.selector);
		account.execute(address(counter), 0, targetCallData);
	}

	function test_ExecuteBatch() public {
		bytes[] memory datas = new bytes[](2);
		address[] memory targets = new address[](2);
		uint256[] memory values = new uint256[](2);
		datas[0] = abi.encodeWithSignature("inc()");
		datas[1] = abi.encodeWithSignature("inc()");
		targets[0] = address(counter);
		targets[1] = address(counter);
		values[0] = 0;
		values[1] = 0;

		vm.prank(address(entryPoint));
		account.executeBatch(targets, values, datas);
		assertEq(counter.x(), 2);
	}

	function test_ExecuteBubblesRevert() public {
		bytes memory targetCallData = abi.encodeWithSignature("boom()");
		vm.prank(address(entryPoint));
		vm.expectRevert(bytes("boom"));
		account.execute(address(reverter), 0, targetCallData);
	}

	function _buildUserOp(bytes memory callData) internal view returns (UserOperation memory) {
		return
			UserOperation({
				sender: address(account),
				nonce: 0,
				initCode: "",
				callData: callData,
				callGasLimit: 0,
				verificationGasLimit: 0,
				preVerificationGas: 0,
				maxFeePerGas: 0,
				maxPriorityFeePerGas: 0,
				paymasterAndData: "",
				signature: ""
			});
	}
}
