import ethers = require('ethers');
var Tx = require('ethereumjs-tx');
import { OnetimeKey } from "../common/models";

export class Utils {
    public async verifySignature(message: string, signature: string): Promise<{isValid: boolean, signerAddress: string, error: string}>{
        let signerAddress: string, errorMsg: string;
        let isValid = false;
        try {
            signerAddress = ethers.Wallet.verifyMessage(message, signature);
            if(signerAddress) isValid = true;
        } catch (error) {
            errorMsg = error;
        }
        return {isValid: isValid, signerAddress: signerAddress, error: errorMsg };
    }

    public buildTransaction(txn: any) {
        if(!txn)
            return null;
        
        let rawTx = {
            from: txn["from"],
            to: txn["to"],
        };
        if (txn["nonce"])
            rawTx["nonce"] = ethers.utils.hexlify(txn["nonce"]);
        if (txn["value"])
            rawTx["value"] = ethers.utils.hexlify(txn["value"]);
        if (txn["gas"])
            rawTx["gasLimit"] = ethers.utils.hexlify(txn["gas"]);
        if (txn["gasLimit"])
            rawTx["gasLimit"] = ethers.utils.hexlify(txn["gasLimit"]);
        if (txn["gasPrice"])
            rawTx["gasPrice"] = ethers.utils.hexlify(txn["gasPrice"]);
        else
            rawTx["gasPrice"] = "0x00";
        if (txn["data"])
            rawTx["data"] = txn["data"];
        if (txn["chainId"])
            rawTx["chainId"] = ethers.utils.hexlify(txn["chainId"]);
        
        return new Tx(rawTx);
    }

    public objToMap(obj: any) {
        const mp = new Map;
        Object.keys(obj). forEach (k => { mp.set(k, obj[k]) });
        return mp;
    }

    public checkIfKeyMapHasAllKeys(keyMap: Array<{partyName:string,onetimeKey:OnetimeKey}>): boolean {
        let hasAllKey = true;
        for(let i = 0; i<keyMap.length;i++) {
            let keyMapItem = keyMap[i];
            if(keyMapItem && !keyMapItem.onetimeKey) {
                hasAllKey = false;
                break;
            }
        }
        return hasAllKey;
    }

    public async sleep(ms) {
        await this._sleep(ms);
    }
    
    private _sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
}