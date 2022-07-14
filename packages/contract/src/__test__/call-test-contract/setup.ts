import type { Interface, JsonAbi } from '@fuel-ts/abi-coder';
import { NativeAssetId } from '@fuel-ts/constants';
import { Provider } from '@fuel-ts/providers';
import type { Wallet } from '@fuel-ts/wallet';
import { TestUtils } from '@fuel-ts/wallet';
import { readFileSync } from 'fs';
import { join } from 'path';

import type Contract from '../../contracts/contract';
import ContractFactory from '../../contracts/contract-factory';

import abiJSON from './out/debug/call-test-abi.json';

const contractBytecode = readFileSync(join(__dirname, './out/debug/call-test.bin'));

let contractInstance: Contract;
const deployContract = async (factory: ContractFactory) => {
  if (contractInstance) return contractInstance;
  contractInstance = await factory.deployContract();
  return contractInstance;
};

let walletInstance: Wallet;
const createWallet = async () => {
  if (walletInstance) return walletInstance;
  const provider = new Provider('http://127.0.0.1:4000/graphql');
  walletInstance = await TestUtils.generateTestWallet(provider, [
    [5_000_000, NativeAssetId],
    [5_000_000, '0x0101010101010101010101010101010101010101010101010101010101010101'],
  ]);
  return walletInstance;
};

export const setup = async (abi: JsonAbi | Interface = abiJSON) => {
  // Create wallet
  const wallet = await createWallet();
  const factory = new ContractFactory(contractBytecode, abi, wallet);
  const contract = await deployContract(factory);
  return contract;
};
