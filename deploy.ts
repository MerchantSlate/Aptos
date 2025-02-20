import {
	AptosClient,
	AptosAccount,
	TxnBuilderTypes,
	BCS,
} from "aptos";
import fs from "fs";
import dotenv from "dotenv";
import * as bip39 from "bip39";
import { execSync } from "child_process";
import { derivePath } from 'ed25519-hd-key';
dotenv.config();

const
	SEED_PHRASE = process.env.SEED_PHRASE || ``,
	compileMoveContract = () => {
		try {
			execSync(`aptos move compile --save-metadata --included-artifacts sparse`, {
				cwd: `.`,
				stdio: "inherit",
			});
		} catch (error) {
			throw new Error("❌ Compilation failed:");
		};
	},
	checkCompile = compileMoveContract(),
	getAptosAccount = (seedPhrase: string): {
		account: AptosAccount,
		accountAddress: string,
		privateKey: string
	} => {
		if (!bip39.validateMnemonic(seedPhrase))
			throw new Error("❌ Invalid seed phrase! Make sure it's correct.");

		const
			path = "m/44'/637'/0'/0'/0'",
			seed = bip39.mnemonicToSeedSync(seedPhrase),
			{ key } = derivePath(path, seed.toString('hex')),
			account = new AptosAccount(new Uint8Array(key)),
			accountAddress = account.address().toString(),
			privateKey = account.toPrivateKeyObject().privateKeyHex;
		return { account, accountAddress, privateKey } // Remove '0x' prefix
	},
	accountObj = getAptosAccount(SEED_PHRASE),
	deployerAccount = accountObj?.account,
	NODE_URL = "https://fullnode.mainnet.aptoslabs.com", // Aptos Mainnet Public RPC, Alternative "https://rpc.ankr.com/http/aptos/v1"
	aptosClient = new AptosClient(NODE_URL),
	getBalance = async (accountAddress: string) => {
		const
			resource = await aptosClient.getAccountResource(accountAddress, '0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>'),
			balance = resource.data
		console.log(`Balance`, JSON.stringify(balance));
	},
	// logBalance = getBalance(accountObj.accountAddress),
	deployMoveModule = async () => {
		console.log("🚀 Deploying Move contract to **Aptos Mainnet**...");

		const
			modulePath = "Move.toml", // Adjust if needed
			moduleBytes = fs.readFileSync(modulePath),
			payload = new TxnBuilderTypes.TransactionPayloadEntryFunction(
				TxnBuilderTypes.EntryFunction.natural(
					"0x1::code",
					"publish_package_txn",
					[],
					[BCS.bcsSerializeBytes(moduleBytes)]
				)
			),
			sequenceDate = await aptosClient.getAccount(accountObj.accountAddress),
			rawTxn = new TxnBuilderTypes.RawTransaction(
				TxnBuilderTypes.AccountAddress.fromHex(accountObj.accountAddress),
				BigInt(sequenceDate.sequence_number),
				payload,
				BigInt(1_000_000), // Gas limit (adjust as needed)
				BigInt(100), // Gas price
				BigInt(Math.floor(Date.now() / 1000) + 600), // Expiration time (10 min)
				new TxnBuilderTypes.ChainId(1) // ✅ **Mainnet uses ChainId = 1**
			),
			bcsTxn = await aptosClient.signTransaction(deployerAccount, rawTxn),
			txnResponse = await aptosClient.submitTransaction(bcsTxn);

		console.log("✅ Transaction submitted:", txnResponse.hash);
		await aptosClient.waitForTransaction(txnResponse.hash);
		console.log("🎉 Move contract deployed successfully to **Aptos Mainnet**!");
	};

// ✅ **Run deployment process**
// deployMoveModule();
execSync(`aptos move publish`, {
	cwd: `.`,
	stdio: "inherit",
});