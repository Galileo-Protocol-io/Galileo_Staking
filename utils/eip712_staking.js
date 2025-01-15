async function sign(wallet, verifyingContract, collectionAddress, tokenId, citizen) {
  try {
    const chainId = 31337;
    const signingDomain = async () => {
      const domain = {
        name: 'Galileo-Staking',
        version: '1',
        verifyingContract: verifyingContract,
        chainId: chainId,
      };
      return domain;
    };

    const domain = await signingDomain();

    const types = {
      GalileoStakeTokens: [
        { name: 'collectionAddress', type: 'address' },
        { name: 'tokenId', type: 'uint256' },
        { name: 'citizen', type: 'uint256' },
        { name: 'chainId', type: 'uint256' },
      ],
    };

    const voucher = {
      collectionAddress,
      tokenId,
      citizen,
      chainId,
    };

    const signature = await wallet.signTypedData(domain, types, voucher);
    const signerAddress = ethers.verifyTypedData(domain, types, voucher, signature);
    // console.log("🚀 ~ signerAddress:", signerAddress)
    return signature;
  } catch (error) {
    throw error;
  }
}

module.exports = { sign };
