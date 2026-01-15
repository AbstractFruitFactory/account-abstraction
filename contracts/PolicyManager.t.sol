// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PolicyManager} from "./PolicyManager.sol";
import {Call} from "./Types.sol";

contract PolicyManagerTest is Test {
	PolicyManager policyManager;
	address account;

	function setUp() public {
		policyManager = new PolicyManager();
		account = address(0xBEEF);
	}

	function test_FreezeBlocksValidation() public {
		vm.prank(account);
		policyManager.freeze();
		Call[] memory calls = _singleCall(address(0xCAFE), 0, abi.encodeWithSignature("ping()"));
		(bool ok, bytes32 reason) = policyManager.validateCall(account, calls);
		assertFalse(ok);
		assertEq(reason, keccak256("FROZEN"));
	}

	function test_TargetAllowlistBlocksUnknownTarget() public {
		vm.prank(account);
		policyManager.setTargetAllowlistEnabled(true);
		vm.prank(account);
		policyManager.setTargetAllowed(address(0xCAFE), true);
		Call[] memory calls = _singleCall(address(0xDEAD), 0, abi.encodeWithSignature("ping()"));
		(bool ok, bytes32 reason) = policyManager.validateCall(account, calls);
		assertFalse(ok);
		assertEq(reason, keccak256("TARGET_NOT_ALLOWED"));
	}

	function test_SelectorAllowlistBlocksUnknownSelector() public {
		vm.prank(account);
		policyManager.setTargetAllowlistEnabled(true);
		vm.prank(account);
		policyManager.setSelectorAllowlistEnabled(true);
		vm.prank(account);
		policyManager.setTargetAllowed(address(0xCAFE), true);
		vm.prank(account);
		policyManager.setSelectorAllowed(address(0xCAFE), bytes4(keccak256("safe()")), true);
		Call[] memory calls = _singleCall(address(0xCAFE), 0, abi.encodeWithSignature("evil()"));
		(bool ok, bytes32 reason) = policyManager.validateCall(account, calls);
		assertFalse(ok);
		assertEq(reason, keccak256("SELECTOR_NOT_ALLOWED"));
	}

	function test_DailyCapBlocksIfExceeded() public {
		vm.prank(account);
		policyManager.setDailyCap(address(0), 1 ether);
		Call[] memory calls = _singleCall(address(0xCAFE), 2 ether, abi.encodeWithSignature("pay()"));
		(bool ok, bytes32 reason) = policyManager.validateCall(account, calls);
		assertFalse(ok);
		assertEq(reason, keccak256("DAILY_CAP"));
	}

	function test_PostExecOnlyAccountUpdatesSpent() public {
		vm.prank(account);
		policyManager.setDailyCap(address(0), 5 ether);
		Call[] memory calls = _singleCall(address(0xCAFE), 2 ether, abi.encodeWithSignature("pay()"));
		policyManager.postExec(account, calls);
		uint256 day = block.timestamp / 1 days;
		assertEq(policyManager.spentPerDay(account, address(0), day), 0);
		vm.prank(account);
		policyManager.postExec(account, calls);
		assertEq(policyManager.spentPerDay(account, address(0), day), 2 ether);
	}

	function _singleCall(address target, uint256 value, bytes memory data) internal pure returns (Call[] memory) {
		Call[] memory calls = new Call[](1);
		calls[0] = Call({target: target, value: value, data: data});
		return calls;
	}
}
