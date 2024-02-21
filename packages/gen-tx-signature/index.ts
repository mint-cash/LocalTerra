import {
  Fee,
  LCDClient,
  MnemonicKey,
  MsgCreateValidator,
  Validator,
} from '@terraclassic-community/terra.js';

const terra = new LCDClient({
  URL: 'https://terra-classic-lcd.publicnode.com',
  chainID: 'columbus-5',
});

const mk = new MnemonicKey({
  mnemonic:
    'satisfy adjust timber high purchase tuition stool faith fine install that you unaware feed domain license impose boss human eager hat rent enjoy dawn',
});

const wallet = terra.wallet(mk);
const description = Validator.Description.fromData({
  moniker: 'columbus-5',
  identity: '',
  website: '',
  security_contact: '',
  details: '',
});
const msgCreateValidator = MsgCreateValidator.fromData({
  '@type': '/cosmos.staking.v1beta1.MsgCreateValidator' as any,
  description,
  commission: {
    rate: '0.100000000000000000',
    max_rate: '0.200000000000000000',
    max_change_rate: '0.010000000000000000',
  },
  min_self_delegation: '1',
  delegator_address: 'terra1dcegyrekltswvyy0xy69ydgxn9x8x32zdtapd8',
  validator_address: 'terravaloper1dcegyrekltswvyy0xy69ydgxn9x8x32zdy3ua5',
  pubkey: {
    '@type': '/cosmos.crypto.ed25519.PubKey',
    key: '/zGmkgCWRFsJLETAzlzYsbu7EHS5HWpaSyR22rlFM68=',
  },
  value: {
    denom: 'uluna',
    amount: '1000000',
  },
});
const fee = new Fee(200000, '120000uluna');

const main = async () => {
  console.log({
    publicKey: wallet.key.publicKey,
    accAddress: wallet.key.accAddress,
    valAddress: wallet.key.valAddress,
  });

  const tx = await wallet.createAndSignTx({
    msgs: [msgCreateValidator],
    memo: '62cd922a9d9349e790247dadd1e32947450502fb@10.10.20.74:26656',
    fee: fee,

    // INIT
    accountNumber: 0,
    sequence: 0,
  });

  console.log(tx);
  // signatures: ["QiMC32NUGHYhSbK5vKqnoPXbInVUDepkFUia4wnGzbhTLTWn7dPpSE2yjEfbhY8rGaCGpUXfdzxaxXPDTbSlaQ=="]
};

main().catch((err) => {
  console.error(err);
});
