<svelte:options runes />
<script lang="ts">
	import { onMount } from 'svelte';
	import {
		createPublicClient,
		createWalletClient,
		custom,
		http,
		parseEther,
		formatEther,
		encodeFunctionData,
		keccak256,
		toHex,
		type Hex
	} from 'viem';
	import { arbitrumSepolia } from 'viem/chains';
	import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';

	const smartAccountAbi = [
		{
			type: 'function',
			name: 'execute',
			stateMutability: 'payable',
			inputs: [
				{ name: 'target', type: 'address' },
				{ name: 'value', type: 'uint256' },
				{ name: 'data', type: 'bytes' }
			],
			outputs: []
		},
		{
			type: 'function',
			name: 'executeBatch',
			stateMutability: 'payable',
			inputs: [
				{ name: 'targets', type: 'address[]' },
				{ name: 'values', type: 'uint256[]' },
				{ name: 'datas', type: 'bytes[]' }
			],
			outputs: []
		},
		{
			type: 'function',
			name: 'setPolicyManager',
			stateMutability: 'nonpayable',
			inputs: [{ name: 'pm', type: 'address' }],
			outputs: []
		},
		{
			type: 'function',
			name: 'setSessionKeyManager',
			stateMutability: 'nonpayable',
			inputs: [{ name: 'skm', type: 'address' }],
			outputs: []
		},
		{
			type: 'function',
			name: 'transferOwnership',
			stateMutability: 'nonpayable',
			inputs: [{ name: 'newOwner', type: 'address' }],
			outputs: []
		}
	] as const;

	const policyManagerAbi = [
		{
			type: 'function',
			name: 'setDailyCap',
			stateMutability: 'nonpayable',
			inputs: [
				{ name: 'token', type: 'address' },
				{ name: 'cap', type: 'uint256' }
			],
			outputs: []
		},
		{
			type: 'function',
			name: 'setTargetAllowlistEnabled',
			stateMutability: 'nonpayable',
			inputs: [{ name: 'value', type: 'bool' }],
			outputs: []
		},
		{
			type: 'function',
			name: 'setSelectorAllowlistEnabled',
			stateMutability: 'nonpayable',
			inputs: [{ name: 'value', type: 'bool' }],
			outputs: []
		},
		{
			type: 'function',
			name: 'setTargetAllowed',
			stateMutability: 'nonpayable',
			inputs: [
				{ name: 'target', type: 'address' },
				{ name: 'allowed', type: 'bool' }
			],
			outputs: []
		},
		{
			type: 'function',
			name: 'setSelectorAllowed',
			stateMutability: 'nonpayable',
			inputs: [
				{ name: 'target', type: 'address' },
				{ name: 'selector', type: 'bytes4' },
				{ name: 'allowed', type: 'bool' }
			],
			outputs: []
		},
		{
			type: 'function',
			name: 'freeze',
			stateMutability: 'nonpayable',
			inputs: [],
			outputs: []
		},
		{
			type: 'function',
			name: 'requestUnfreeze',
			stateMutability: 'nonpayable',
			inputs: [],
			outputs: []
		},
		{
			type: 'function',
			name: 'unfreeze',
			stateMutability: 'nonpayable',
			inputs: [],
			outputs: []
		},
		{
			type: 'function',
			name: 'spentPerDay',
			stateMutability: 'view',
			inputs: [
				{ name: 'account', type: 'address' },
				{ name: 'token', type: 'address' },
				{ name: 'day', type: 'uint256' }
			],
			outputs: [{ name: 'spent', type: 'uint256' }]
		}
	] as const;

	const sessionKeyManagerAbi = [
		{
			type: 'function',
			name: 'createSessionKey',
			stateMutability: 'nonpayable',
			inputs: [
				{ name: 'sessionKey', type: 'address' },
				{
					name: 'cfg',
					type: 'tuple',
					components: [
						{ name: 'validAfter', type: 'uint64' },
						{ name: 'validUntil', type: 'uint64' },
						{ name: 'maxValuePerTx', type: 'uint256' },
						{ name: 'targetAllowlistEnabled', type: 'bool' },
						{ name: 'selectorAllowlistEnabled', type: 'bool' }
					]
				},
				{ name: 'targets', type: 'address[]' },
				{ name: 'selectors', type: 'bytes4[][]' }
			],
			outputs: []
		},
		{
			type: 'function',
			name: 'revokeSessionKey',
			stateMutability: 'nonpayable',
			inputs: [{ name: 'sessionKey', type: 'address' }],
			outputs: []
		}
	] as const;

	const entryPointAbi = [
		{
			type: 'function',
			name: 'getUserOpHash',
			stateMutability: 'view',
			inputs: [
				{
					name: 'userOp',
					type: 'tuple',
					components: [
						{ name: 'sender', type: 'address' },
						{ name: 'nonce', type: 'uint256' },
						{ name: 'initCode', type: 'bytes' },
						{ name: 'callData', type: 'bytes' },
						{ name: 'callGasLimit', type: 'uint256' },
						{ name: 'verificationGasLimit', type: 'uint256' },
						{ name: 'preVerificationGas', type: 'uint256' },
						{ name: 'maxFeePerGas', type: 'uint256' },
						{ name: 'maxPriorityFeePerGas', type: 'uint256' },
						{ name: 'paymasterAndData', type: 'bytes' },
						{ name: 'signature', type: 'bytes' }
					]
				}
			],
			outputs: [{ name: 'hash', type: 'bytes32' }]
		}
	] as const;

	type UserOp = {
		sender: `0x${string}`;
		nonce: bigint;
		initCode: Hex;
		callData: Hex;
		callGasLimit: bigint;
		verificationGasLimit: bigint;
		preVerificationGas: bigint;
		maxFeePerGas: bigint;
		maxPriorityFeePerGas: bigint;
		paymasterAndData: Hex;
		signature: Hex;
	};

	type UserOpStatus = {
		hash: Hex;
		status: 'pending' | 'included' | 'failed';
		receipt?: Record<string, unknown> | null;
		error?: string;
	};

	type AppState = {
		rpcUrl: string;
		bundlerUrl: string;
		entryPoint: string;
		policyManager: string;
		sessionKeyManager: string;
		smartAccount: string;
		ownerAddress: string;
		smartAccountBalance: string;
		depositAmount: string;
		nonce: string;
		callGasLimit: string;
		verificationGasLimit: string;
		preVerificationGas: string;
		maxFeePerGas: string;
		maxPriorityFeePerGas: string;
		paymasterAndData: string;
		policyTarget: string;
		policySelector: string;
		policyCap: string;
		policyTargetAllowlistEnabled: boolean;
		policySelectorAllowlistEnabled: boolean;
		sessionKeyPrivateKey: string;
		sessionKeyAddress: string;
		sessionValidAfter: string;
		sessionValidUntil: string;
		sessionMaxValue: string;
		sessionTargetAllowlistEnabled: boolean;
		sessionSelectorAllowlistEnabled: boolean;
		sessionScopeTarget: string;
		sessionScopeSelectors: string;
		sendTarget: string;
		sendValue: string;
		demoDapp: string;
		maliciousTarget: string;
		useSessionKey: boolean;
		userOps: UserOpStatus[];
		todaySpent: string;
	};

	type Eip1193Provider = {
		request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
	};

	let publicClient = $state(null as ReturnType<typeof createPublicClient> | null);
	let walletClient = $state(null as ReturnType<typeof createWalletClient> | null);
	let hasProvider = $state(false);
	let status = $state('');
	let state: AppState = $state({
		rpcUrl: 'https://sepolia-rollup.arbitrum.io/rpc',
		bundlerUrl: '',
		entryPoint: '',
		policyManager: '',
		sessionKeyManager: '',
		smartAccount: '',
		ownerAddress: '',
		smartAccountBalance: '',
		depositAmount: '0.01',
		nonce: '0',
		callGasLimit: '200000',
		verificationGasLimit: '200000',
		preVerificationGas: '50000',
		maxFeePerGas: '',
		maxPriorityFeePerGas: '',
		paymasterAndData: '0x',
		policyTarget: '',
		policySelector: '',
		policyCap: '0',
		policyTargetAllowlistEnabled: true,
		policySelectorAllowlistEnabled: true,
		sessionKeyPrivateKey: '',
		sessionKeyAddress: '',
		sessionValidAfter: '0',
		sessionValidUntil: '',
		sessionMaxValue: '0',
		sessionTargetAllowlistEnabled: true,
		sessionSelectorAllowlistEnabled: true,
		sessionScopeTarget: '',
		sessionScopeSelectors: '',
		sendTarget: '',
		sendValue: '0.001',
		demoDapp: '',
		maliciousTarget: '',
		useSessionKey: false,
		userOps: [] as UserOpStatus[],
		todaySpent: ''
	});

	onMount(() => {
		const provider = (window as Window & { ethereum?: Eip1193Provider }).ethereum;
		hasProvider = !!provider;
		const storedKey = localStorage.getItem('sessionKeyPrivateKey');
		if (storedKey) {
			const account = privateKeyToAccount(storedKey as Hex);
			state.sessionKeyPrivateKey = storedKey;
			state.sessionKeyAddress = account.address;
		}
	});

	$effect(() => {
		if (state.sessionKeyPrivateKey) {
			localStorage.setItem('sessionKeyPrivateKey', state.sessionKeyPrivateKey);
		} else {
			localStorage.removeItem('sessionKeyPrivateKey');
		}
	});

	$effect(() => {
		if (!state.rpcUrl) return;
		publicClient = createPublicClient({
			chain: arbitrumSepolia,
			transport: http(state.rpcUrl)
		});
	});

	async function connectWallet() {
		status = '';
		if (!hasProvider) {
			status = 'No wallet detected';
			return;
		}
		const provider = (window as Window & { ethereum?: Eip1193Provider }).ethereum;
		if (!provider) return;
		walletClient = createWalletClient({
			chain: arbitrumSepolia,
			transport: custom(provider)
		});
		const [address] = await walletClient.requestAddresses();
		state.ownerAddress = address;
		if (!state.maxFeePerGas && publicClient) {
			const gasPrice = await publicClient.getGasPrice();
			state.maxFeePerGas = gasPrice.toString();
			state.maxPriorityFeePerGas = gasPrice.toString();
		}
	}

	async function refreshBalance() {
		if (!publicClient || !state.smartAccount) return;
		const balance = await publicClient.getBalance({ address: state.smartAccount as `0x${string}` });
		state.smartAccountBalance = formatEther(balance);
	}

	async function deposit() {
		if (!walletClient || !state.smartAccount || !state.ownerAddress) return;
		const hash = await walletClient.sendTransaction({
			chain: arbitrumSepolia,
			account: state.ownerAddress as `0x${string}`,
			to: state.smartAccount as `0x${string}`,
			value: parseEther(state.depositAmount)
		});
		status = `Deposit tx ${hash}`;
	}

	function selectorFromInput(input: string) {
		if (input.startsWith('0x') && input.length === 10) return input as Hex;
		const hash = keccak256(toHex(input));
		return (`0x${hash.slice(2, 10)}` as Hex);
	}

	function encodeSelectorOnly(signature: string) {
		const selector = selectorFromInput(signature);
		return selector;
	}

	function toBigInt(value: string, fallback = 0n) {
		try {
			return BigInt(value);
		} catch {
			return fallback;
		}
	}

	async function buildUserOp(callData: Hex): Promise<UserOp> {
		if (!publicClient) throw new Error('No public client');
		if (!state.entryPoint || !state.smartAccount) throw new Error('Missing entry point or smart account');
		const userOp: UserOp = {
			sender: state.smartAccount as `0x${string}`,
			nonce: toBigInt(state.nonce),
			initCode: '0x',
			callData,
			callGasLimit: toBigInt(state.callGasLimit),
			verificationGasLimit: toBigInt(state.verificationGasLimit),
			preVerificationGas: toBigInt(state.preVerificationGas),
			maxFeePerGas: toBigInt(state.maxFeePerGas),
			maxPriorityFeePerGas: toBigInt(state.maxPriorityFeePerGas),
			paymasterAndData: state.paymasterAndData as Hex,
			signature: '0x'
		};
		const userOpHash = await publicClient.readContract({
			address: state.entryPoint as `0x${string}`,
			abi: entryPointAbi,
			functionName: 'getUserOpHash',
			args: [userOp]
		});
		const signature = await signUserOp(userOpHash as Hex);
		return { ...userOp, signature };
	}

	async function signUserOp(userOpHash: Hex): Promise<Hex> {
		if (state.useSessionKey) {
			if (!state.sessionKeyPrivateKey) throw new Error('Missing session key');
			const account = privateKeyToAccount(state.sessionKeyPrivateKey as Hex);
			return (await account.signMessage({ message: { raw: userOpHash } })) as Hex;
		}
		if (!walletClient || !state.ownerAddress) throw new Error('Missing owner wallet');
		return (await walletClient.signMessage({
			account: state.ownerAddress as `0x${string}`,
			message: { raw: userOpHash }
		})) as Hex;
	}

	async function bundlerRpc(method: string, params: unknown[]) {
		const response = await fetch(state.bundlerUrl, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ id: 1, jsonrpc: '2.0', method, params })
		});
		const json = await response.json();
		if (json.error) throw new Error(json.error.message || 'Bundler error');
		return json.result;
	}

	async function sendUserOp(callData: Hex) {
		status = '';
		const userOp = await buildUserOp(callData);
		const userOpHash = (await bundlerRpc('eth_sendUserOperation', [
			userOp,
			state.entryPoint
		])) as Hex;
		state.userOps = [{ hash: userOpHash, status: 'pending', receipt: null }, ...state.userOps];
		status = `UserOp sent ${userOpHash}`;
	}

	async function refreshUserOp(op: UserOpStatus) {
		try {
			const receipt = await bundlerRpc('eth_getUserOperationReceipt', [op.hash]);
			if (!receipt) {
				op.status = 'pending';
				op.receipt = null;
				return;
			}
			op.status = receipt.success ? 'included' : 'failed';
			op.receipt = receipt;
		} catch (err) {
			op.status = 'failed';
			op.error = err instanceof Error ? err.message : 'Unknown error';
		}
		state.userOps = [...state.userOps];
	}

	async function submitAccountCall(target: string, value: string, data: Hex) {
		const callData = encodeFunctionData({
			abi: smartAccountAbi,
			functionName: 'execute',
			args: [target as `0x${string}`, parseEther(value), data]
		});
		await sendUserOp(callData);
	}

	async function submitBatch(targets: string[], values: string[], datas: Hex[]) {
		const callData = encodeFunctionData({
			abi: smartAccountAbi,
			functionName: 'executeBatch',
			args: [
				targets as `0x${string}`[],
				values.map((v) => parseEther(v)),
				datas
			]
		});
		await sendUserOp(callData);
	}

	async function updatePolicyCap() {
		const data = encodeFunctionData({
			abi: policyManagerAbi,
			functionName: 'setDailyCap',
			args: ['0x0000000000000000000000000000000000000000', parseEther(state.policyCap)]
		});
		await submitAccountCall(state.policyManager, '0', data);
	}

	async function updateAllowlistToggles() {
		const dataTargets = encodeFunctionData({
			abi: policyManagerAbi,
			functionName: 'setTargetAllowlistEnabled',
			args: [state.policyTargetAllowlistEnabled]
		});
		const dataSelectors = encodeFunctionData({
			abi: policyManagerAbi,
			functionName: 'setSelectorAllowlistEnabled',
			args: [state.policySelectorAllowlistEnabled]
		});
		await submitBatch(
			[state.policyManager, state.policyManager],
			['0', '0'],
			[dataTargets, dataSelectors]
		);
	}

	async function updateAllowlistEntry(allowed: boolean) {
		const target = state.policyTarget;
		if (!target) return;
		const data = encodeFunctionData({
			abi: policyManagerAbi,
			functionName: 'setTargetAllowed',
			args: [target as `0x${string}`, allowed]
		});
		await submitAccountCall(state.policyManager, '0', data);
	}

	async function updateSelectorEntry(allowed: boolean) {
		const target = state.policyTarget;
		const selector = selectorFromInput(state.policySelector);
		if (!target || !selector) return;
		const data = encodeFunctionData({
			abi: policyManagerAbi,
			functionName: 'setSelectorAllowed',
			args: [target as `0x${string}`, selector, allowed]
		});
		await submitAccountCall(state.policyManager, '0', data);
	}

	async function freezeAccount() {
		const data = encodeFunctionData({
			abi: policyManagerAbi,
			functionName: 'freeze',
			args: []
		});
		await submitAccountCall(state.policyManager, '0', data);
	}

	async function requestUnfreeze() {
		const data = encodeFunctionData({
			abi: policyManagerAbi,
			functionName: 'requestUnfreeze',
			args: []
		});
		await submitAccountCall(state.policyManager, '0', data);
	}

	async function unfreeze() {
		const data = encodeFunctionData({
			abi: policyManagerAbi,
			functionName: 'unfreeze',
			args: []
		});
		await submitAccountCall(state.policyManager, '0', data);
	}

	async function refreshTodaySpent() {
		if (!publicClient || !state.policyManager || !state.smartAccount) return;
		const day = Math.floor(Date.now() / 1000 / 86400);
		const spent = await publicClient.readContract({
			address: state.policyManager as `0x${string}`,
			abi: policyManagerAbi,
			functionName: 'spentPerDay',
			args: [state.smartAccount as `0x${string}`, '0x0000000000000000000000000000000000000000', BigInt(day)]
		});
		state.todaySpent = formatEther(spent as bigint);
	}

	function generateSessionKey() {
		const pk = generatePrivateKey();
		const account = privateKeyToAccount(pk);
		state.sessionKeyPrivateKey = pk;
		state.sessionKeyAddress = account.address;
	}

	async function createSessionKey() {
		if (!state.sessionKeyAddress || !state.sessionKeyManager) return;
		const targets = state.sessionScopeTarget ? [state.sessionScopeTarget] : [];
		const selectorList = state.sessionScopeSelectors
			.split(',')
			.map((s: string) => s.trim())
			.filter(Boolean)
			.map((s: string) => selectorFromInput(s));
		const selectors = targets.length
			? [selectorList]
			: [];
		const cfg = {
			validAfter: BigInt(state.sessionValidAfter || '0'),
			validUntil: BigInt(state.sessionValidUntil || '0'),
			maxValuePerTx: parseEther(state.sessionMaxValue || '0'),
			targetAllowlistEnabled: state.sessionTargetAllowlistEnabled,
			selectorAllowlistEnabled: state.sessionSelectorAllowlistEnabled
		};
		const data = encodeFunctionData({
			abi: sessionKeyManagerAbi,
			functionName: 'createSessionKey',
			args: [
				state.sessionKeyAddress as `0x${string}`,
				cfg,
				targets as `0x${string}`[],
				selectors as Hex[][]
			]
		});
		await submitAccountCall(state.sessionKeyManager, '0', data);
	}

	async function revokeSessionKey() {
		if (!state.sessionKeyAddress || !state.sessionKeyManager) return;
		const data = encodeFunctionData({
			abi: sessionKeyManagerAbi,
			functionName: 'revokeSessionKey',
			args: [state.sessionKeyAddress as `0x${string}`]
		});
		await submitAccountCall(state.sessionKeyManager, '0', data);
	}

	async function sendSmallEth() {
		if (!state.sendTarget) return;
		await submitAccountCall(state.sendTarget, state.sendValue, '0x');
	}

	async function callDemoSafe() {
		if (!state.demoDapp) return;
		const data = encodeSelectorOnly('safeFunction()');
		await submitAccountCall(state.demoDapp, '0', data);
	}

	async function callMalicious() {
		if (!state.maliciousTarget) return;
		const data = encodeSelectorOnly('rugPull()');
		await submitAccountCall(state.maliciousTarget, '0', data);
	}
</script>

<main>
	<header>
		<h1>Spending Guard Smart Account</h1>
		<p>Arbitrum Sepolia demo console</p>
	</header>

	<section>
		<h2>Landing / Create Account</h2>
		<div class="grid">
			<div class="card">
				<label>RPC URL<input bind:value={state.rpcUrl} /></label>
				<label>Bundler URL<input bind:value={state.bundlerUrl} placeholder="https://bundler.example/rpc" /></label>
				<label>EntryPoint<input bind:value={state.entryPoint} placeholder="0x..." /></label>
				<label>PolicyManager<input bind:value={state.policyManager} placeholder="0x..." /></label>
				<label>SessionKeyManager<input bind:value={state.sessionKeyManager} placeholder="0x..." /></label>
				<label>SmartAccount<input bind:value={state.smartAccount} placeholder="0x..." /></label>
				<label>Owner<input value={state.ownerAddress} readonly /></label>
				<button onclick={connectWallet} disabled={!hasProvider}>
					Connect Wallet
				</button>
			</div>
			<div class="card">
				<label>Smart Account Balance<input value={state.smartAccountBalance} readonly /></label>
				<div class="row">
					<button onclick={refreshBalance}>Refresh</button>
				</div>
				<label>Deposit ETH<input bind:value={state.depositAmount} /></label>
				<div class="row">
					<button onclick={deposit}>Deposit</button>
				</div>
				<label class="row">
					<input type="checkbox" bind:checked={state.useSessionKey} />
					<span>Use session key for signing</span>
				</label>
				<label>Status<input value={status} readonly /></label>
			</div>
		</div>
	</section>

	<section>
		<h2>Policies</h2>
		<div class="grid">
			<div class="card">
				<label>Daily Cap (ETH)<input bind:value={state.policyCap} /></label>
				<div class="row">
					<button onclick={updatePolicyCap}>Set Cap</button>
				</div>
				<label class="row">
					<input type="checkbox" bind:checked={state.policyTargetAllowlistEnabled} />
					<span>Target allowlist enabled</span>
				</label>
				<label class="row">
					<input type="checkbox" bind:checked={state.policySelectorAllowlistEnabled} />
					<span>Selector allowlist enabled</span>
				</label>
				<button onclick={updateAllowlistToggles}>Update Allowlist Toggles</button>
			</div>
			<div class="card">
				<label>Allowlist Target<input bind:value={state.policyTarget} placeholder="0x..." /></label>
				<label>Selector<input bind:value={state.policySelector} placeholder="safeFunction() or 0x12345678" /></label>
				<div class="row">
					<button onclick={() => updateAllowlistEntry(true)}>Allow Target</button>
					<button onclick={() => updateAllowlistEntry(false)}>Remove Target</button>
				</div>
				<div class="row">
					<button onclick={() => updateSelectorEntry(true)}>Allow Selector</button>
					<button onclick={() => updateSelectorEntry(false)}>Remove Selector</button>
				</div>
			</div>
			<div class="card">
				<div class="label">Freeze</div>
				<div class="row">
					<button onclick={freezeAccount}>Freeze</button>
					<button onclick={requestUnfreeze}>Request Unfreeze</button>
					<button onclick={unfreeze}>Unfreeze</button>
				</div>
				<label>Today Spent (ETH)<input value={state.todaySpent} readonly /></label>
				<div class="row">
					<button onclick={refreshTodaySpent}>Refresh</button>
				</div>
			</div>
		</div>
	</section>

	<section>
		<h2>Session Keys</h2>
		<div class="grid">
			<div class="card">
				<label>Session Key Private Key<input bind:value={state.sessionKeyPrivateKey} placeholder="0x..." /></label>
				<label>Session Key Address<input value={state.sessionKeyAddress} readonly /></label>
				<button onclick={generateSessionKey}>Generate Session Key</button>
			</div>
			<div class="card">
				<label>Valid After (unix)<input bind:value={state.sessionValidAfter} /></label>
				<label>Valid Until (unix)<input bind:value={state.sessionValidUntil} /></label>
				<label>Max Value Per Tx (ETH)<input bind:value={state.sessionMaxValue} /></label>
				<label class="row">
					<input type="checkbox" bind:checked={state.sessionTargetAllowlistEnabled} />
					<span>Target allowlist enabled</span>
				</label>
				<label class="row">
					<input type="checkbox" bind:checked={state.sessionSelectorAllowlistEnabled} />
					<span>Selector allowlist enabled</span>
				</label>
			</div>
			<div class="card">
				<label>Scope Target<input bind:value={state.sessionScopeTarget} placeholder="0x..." /></label>
				<label>Scope Selectors<input bind:value={state.sessionScopeSelectors} placeholder="safeFunction(),0x12345678" /></label>
				<div class="row">
					<button onclick={createSessionKey}>Create Session Key</button>
					<button onclick={revokeSessionKey}>Revoke Session Key</button>
				</div>
			</div>
		</div>
	</section>

	<section>
		<h2>Actions</h2>
		<div class="grid">
			<div class="card">
				<label>Send Small ETH<input bind:value={state.sendTarget} placeholder="0x recipient" /></label>
				<div class="row">
					<label class="row">
						<span>Value</span>
						<input bind:value={state.sendValue} />
					</label>
					<button onclick={sendSmallEth}>Send</button>
				</div>
			</div>
			<div class="card">
				<label>Demo Dapp<input bind:value={state.demoDapp} placeholder="0x demo dapp" /></label>
				<button onclick={callDemoSafe}>Call safeFunction()</button>
			</div>
			<div class="card">
				<label>Malicious Target<input bind:value={state.maliciousTarget} placeholder="0x malicious" /></label>
				<button onclick={callMalicious}>Attempt rugPull()</button>
			</div>
		</div>
	</section>

	<section>
		<h2>UserOp Monitor</h2>
		<div class="card">
			<label>Nonce<input bind:value={state.nonce} /></label>
			<label>Call Gas Limit<input bind:value={state.callGasLimit} /></label>
			<label>Verification Gas Limit<input bind:value={state.verificationGasLimit} /></label>
			<label>Pre Verification Gas<input bind:value={state.preVerificationGas} /></label>
			<label>Max Fee Per Gas<input bind:value={state.maxFeePerGas} /></label>
			<label>Max Priority Fee Per Gas<input bind:value={state.maxPriorityFeePerGas} /></label>
			<label>Paymaster And Data<input bind:value={state.paymasterAndData} /></label>
		</div>
		<div class="card">
			{#if state.userOps.length === 0}
				<p>No UserOps submitted yet.</p>
			{:else}
				<table>
					<thead>
						<tr>
							<th>Hash</th>
							<th>Status</th>
							<th>Actions</th>
						</tr>
					</thead>
					<tbody>
						{#each state.userOps as op}
							<tr>
								<td>{op.hash}</td>
								<td>{op.status}</td>
								<td>
									<button onclick={() => refreshUserOp(op)}>Refresh</button>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			{/if}
		</div>
	</section>
</main>

<style>
	:global(body) {
		margin: 0;
		background: radial-gradient(circle at top, #eef2ff 0%, #f8fafc 45%, #ffffff 100%);
		color: #0f172a;
	}
	main {
		display: flex;
		flex-direction: column;
		gap: 2.5rem;
		padding: 3rem clamp(1.5rem, 4vw, 3.5rem) 4rem;
		font-family: 'Inter', system-ui, sans-serif;
		max-width: 1200px;
		margin: 0 auto;
	}
	header {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	header h1 {
		margin: 0;
		font-size: clamp(1.8rem, 3vw, 2.5rem);
		letter-spacing: -0.02em;
	}
	header p {
		margin: 0;
		opacity: 0.7;
		font-size: 1rem;
	}
	section {
		display: flex;
		flex-direction: column;
		gap: 1.2rem;
	}
	section h2 {
		margin: 0;
		font-size: 1.15rem;
		letter-spacing: 0.01em;
		text-transform: uppercase;
		color: #475569;
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
		gap: 1.2rem;
	}
	.card {
		border: 1px solid #e2e8f0;
		border-radius: 16px;
		padding: 1.25rem;
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		background: rgba(255, 255, 255, 0.9);
		box-shadow: 0 12px 30px rgba(15, 23, 42, 0.08);
		backdrop-filter: blur(8px);
	}
	label {
		font-size: 0.85rem;
		color: #475569;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.label {
		font-size: 0.85rem;
		color: #475569;
	}
	input {
		padding: 0.55rem 0.7rem;
		border: 1px solid #cbd5f5;
		border-radius: 10px;
		font-size: 0.9rem;
		background: #fff;
		color: #0f172a;
		transition:
			border-color 0.15s ease,
			box-shadow 0.15s ease;
	}
	input:focus {
		outline: none;
		border-color: #6366f1;
		box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.2);
	}
	button {
		padding: 0.55rem 0.9rem;
		border-radius: 10px;
		border: 1px solid transparent;
		background: linear-gradient(135deg, #4f46e5, #7c3aed);
		color: #fff;
		cursor: pointer;
		font-weight: 600;
		letter-spacing: 0.01em;
		transition:
			transform 0.15s ease,
			box-shadow 0.15s ease,
			opacity 0.15s ease;
	}
	button:hover {
		transform: translateY(-1px);
		box-shadow: 0 8px 20px rgba(79, 70, 229, 0.25);
	}
	button:disabled {
		opacity: 0.5;
		cursor: not-allowed;
		transform: none;
		box-shadow: none;
	}
	.row {
		display: flex;
		gap: 0.6rem;
		align-items: center;
		flex-wrap: wrap;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		background: #fff;
		border-radius: 12px;
		overflow: hidden;
	}
	th,
	td {
		border-bottom: 1px solid #e2e8f0;
		text-align: left;
		padding: 0.65rem;
		font-size: 0.85rem;
	}
	th {
		background: #f8fafc;
		color: #475569;
		text-transform: uppercase;
		font-size: 0.75rem;
		letter-spacing: 0.05em;
	}
</style>
