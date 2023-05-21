import argparse
import json
import pprint

import mpt
import rlp
import sha3

from mpt import MerklePatriciaTrie

def keccak256(x):
    k = sha3.keccak_256()
    k.update(bytearray.fromhex(x))
    return k.hexdigest()

def serialize_hex(val_hex):
    val_arr = [int(nib, 16) for nib in val_hex]
    return val_arr


def get_block_pf(block, debug=False):
    block_list = [
        bytearray.fromhex(block['parentHash'][2:]),
        bytearray.fromhex(block['sha3Uncles'][2:]),
        bytearray.fromhex(block['miner'][2:]),
        bytearray.fromhex(block['stateRoot'][2:]),
        bytearray.fromhex(block['transactionsRoot'][2:]),
        bytearray.fromhex(block['receiptsRoot'][2:]),
        bytearray.fromhex(block['logsBloom'][2:]),
        int(block['difficulty'], 16),
        int(block['number'], 16),
        int(block['gasLimit'], 16),
        int(block['gasUsed'], 16),
        int(block['timestamp'], 16),
        bytearray.fromhex(block['extraData'][2:]),
        bytearray.fromhex(block['mixHash'][2:]),
        bytearray.fromhex(block['nonce'][2:]),
        int(block['baseFeePerGas'], 16)
    ]
    rlp_block = rlp.encode(block_list).hex()
    print(rlp_block, len(rlp_block))
    print(keccak256(rlp_block))
    print('Hash: ' + block['hash'])
    print('Number: ' + block['number'])
    for x in block_list:
        print(len(rlp.encode(x).hex()), x)

    # if args.debug:
    #     rlp_prefix = rlp_block[:2]
    #     print('rlp(block): {}'.format(rlp_block))
    #     print('rlp_prefix: {}'.format(rlp_prefix))
    
    ret = {
        "blockRlpHexs": serialize_hex(rlp_block) + [0 for x in range(1112 - len(rlp_block))],
    }
    print(ret)
    return ret