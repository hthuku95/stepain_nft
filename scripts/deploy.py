from brownie import SneakerNFT, network, config
from scripts.helpful_scripts import get_account
from web3 import Web3

def main():
    account = get_account()
    sneaker_nft = SneakerNFT.deploy(
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify", False)
    )
    print(sneaker_nft.name())


'''
bscscan link: https://testnet.bscscan.com/address/0xccd60e519b2dfc80e807d0bb4efebc998a0bb797
'''