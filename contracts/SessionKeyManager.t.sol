// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SessionKeyManager} from "./SessionKeyManager.sol";
import {Call} from "./Types.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SessionKeyManagerTest is Test {
	using MessageHashUtils for bytes32;

	SessionKeyManager sessionKeyManager;
	address account;
	uint256 sessionKey;
	address sessionKeyAddr;

	function setUp() public {
		sessionKeyManager = new SessionKeyManager();
		account = address(0xBEEF);
		sessionKey = 0xB0B;
		sessionKeyAddr = vm.addr(sessionKey);
	}

	function test_SessionKeyAcceptedWithinScope() public {
		address target = address(0xCAFE);
		bytes4 selector = bytes4(keccak256("safe()"));
		_createSession(true, true, 0, uint64(block.timestamp + 1 days), 0, target, selector);
		Call[] memory calls = _singleCall(target, 0, abi.encodeWithSignature("safe()"));
		bytes memory sig = _sign(userOpHash(), sessionKey);
		(bool ok, ) = sessionKeyManager.isSessionKeyValid(account, userOpHash(), sig, calls, 0);
		assertTrue(ok);
	}

	function test_RejectedIfExpired() public {
		address target = address(0xCAFE);
		bytes4 selector = bytes4(keccak256("safe()"));
		_createSession(true, true, 0, uint64(block.timestamp + 1), 0, target, selector);
		vm.warp(block.timestamp + 2);
		Call[] memory calls = _singleCall(target, 0, abi.encodeWithSignature("safe()"));
		bytes memory sig = _sign(userOpHash(), sessionKey);
		(bool ok, bytes32 reason) = sessionKeyManager.isSessionKeyValid(account, userOpHash(), sig, calls, 0);
		assertFalse(ok);
		assertEq(reason, keccak256("SESSION_TIME"));
	}

	function test_RejectedIfNotYetValid() public {
		address target = address(0xCAFE);
		bytes4 selector = bytes4(keccak256("safe()"));
		_createSession(true, true, uint64(block.timestamp + 1), uint64(block.timestamp + 2 days), 0, target, selector);
		Call[] memory calls = _singleCall(target, 0, abi.encodeWithSignature("safe()"));
		bytes memory sig = _sign(userOpHash(), sessionKey);
		(bool ok, bytes32 reason) = sessionKeyManager.isSessionKeyValid(account, userOpHash(), sig, calls, 0);
		assertFalse(ok);
		assertEq(reason, keccak256("SESSION_TIME"));
	}

	function test_RejectedIfTargetNotAllowed() public {
		address target = address(0xCAFE);
		bytes4 selector = bytes4(keccak256("safe()"));
		_createSession(true, true, 0, uint64(block.timestamp + 1 days), 0, target, selector);
		Call[] memory calls = _singleCall(address(0xDEAD), 0, abi.encodeWithSignature("safe()"));
		bytes memory sig = _sign(userOpHash(), sessionKey);
		(bool ok, bytes32 reason) = sessionKeyManager.isSessionKeyValid(account, userOpHash(), sig, calls, 0);
		assertFalse(ok);
		assertEq(reason, keccak256("SESSION_SCOPE"));
	}

	function test_RejectedIfSelectorNotAllowed() public {
		address target = address(0xCAFE);
		bytes4 selector = bytes4(keccak256("safe()"));
		_createSession(true, true, 0, uint64(block.timestamp + 1 days), 0, target, selector);
		Call[] memory calls = _singleCall(target, 0, abi.encodeWithSignature("evil()"));
		bytes memory sig = _sign(userOpHash(), sessionKey);
		(bool ok, bytes32 reason) = sessionKeyManager.isSessionKeyValid(account, userOpHash(), sig, calls, 0);
		assertFalse(ok);
		assertEq(reason, keccak256("SESSION_SCOPE"));
	}

	function test_RejectedIfValueExceedsMax() public {
		address target = address(0xCAFE);
		bytes4 selector = bytes4(keccak256("safe()"));
		_createSession(true, true, 0, uint64(block.timestamp + 1 days), 1 ether, target, selector);
		Call[] memory calls = _singleCall(target, 2 ether, abi.encodeWithSignature("safe()"));
		bytes memory sig = _sign(userOpHash(), sessionKey);
		(bool ok, bytes32 reason) = sessionKeyManager.isSessionKeyValid(account, userOpHash(), sig, calls, 0);
		assertFalse(ok);
		assertEq(reason, keccak256("SESSION_VALUE"));
	}

	function test_RevokeWorks() public {
		address target = address(0xCAFE);
		bytes4 selector = bytes4(keccak256("safe()"));
		_createSession(true, true, 0, uint64(block.timestamp + 1 days), 0, target, selector);
		vm.prank(account);
		sessionKeyManager.revokeSessionKey(sessionKeyAddr);
		Call[] memory calls = _singleCall(target, 0, abi.encodeWithSignature("safe()"));
		bytes memory sig = _sign(userOpHash(), sessionKey);
		(bool ok, bytes32 reason) = sessionKeyManager.isSessionKeyValid(account, userOpHash(), sig, calls, 0);
		assertFalse(ok);
		assertEq(reason, keccak256("SESSION_DISABLED"));
	}

	function _createSession(
		bool targetAllowlistEnabled,
		bool selectorAllowlistEnabled,
		uint64 validAfter,
		uint64 validUntil,
		uint256 maxValue,
		address target,
		bytes4 selector
	) internal {
		address[] memory targets = new address[](1);
		targets[0] = target;
		bytes4[][] memory selectors = new bytes4[][](1);
		selectors[0] = new bytes4[](1);
		selectors[0][0] = selector;
		SessionKeyManager.SessionConfig memory cfg = SessionKeyManager.SessionConfig({
			validAfter: validAfter,
			validUntil: validUntil,
			maxValuePerTx: maxValue,
			targetAllowlistEnabled: targetAllowlistEnabled,
			selectorAllowlistEnabled: selectorAllowlistEnabled
		});
		vm.prank(account);
		sessionKeyManager.createSessionKey(sessionKeyAddr, cfg, targets, selectors);
	}

	function _singleCall(address target, uint256 value, bytes memory data) internal pure returns (Call[] memory) {
		Call[] memory calls = new Call[](1);
		calls[0] = Call({target: target, value: value, data: data});
		return calls;
	}

	function _sign(bytes32 hash, uint256 key) internal pure returns (bytes memory) {
		bytes32 digest = hash.toEthSignedMessageHash();
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
		return abi.encodePacked(r, s, v);
	}

	function userOpHash() internal pure returns (bytes32) {
		return keccak256("userOp");
	}
}
