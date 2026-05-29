#!/usr/bin/env python3
"""
Funding Wallet Checker
Check the status of your main funding wallets for devnet and mainnet.
"""

import os
import subprocess
import sys
from pathlib import Path

def check_funding_wallet(network):
    """Check funding wallet status for a network."""
    funding_wallet_dir = os.path.expanduser('~/.solana-wallets')
    funding_wallet_path = os.path.join(funding_wallet_dir, f'funding-{network}.json')
    
    print(f"\n💰 {network.upper()} Funding Wallet:")
    print("=" * 40)
    
    if not os.path.exists(funding_wallet_path):
        print(f"❌ No funding wallet found for {network}")
        print(f"   Will be created on first {network} deployment")
        return
    
    try:
        # Get wallet address
        result = subprocess.run(['solana-keygen', 'pubkey', funding_wallet_path], 
                               capture_output=True, text=True, check=True)
        wallet_address = result.stdout.strip()
        
        # Get balance
        url_param = network if network == 'devnet' else 'mainnet-beta'
        balance_result = subprocess.run(['solana', 'balance', wallet_address, '--url', url_param], 
                                      capture_output=True, text=True, check=True)
        balance = float(balance_result.stdout.split()[0])
        
        print(f"📍 Address: {wallet_address}")
        print(f"💰 Balance: {balance} SOL")
        
        if network == 'mainnet':
            if balance < 1.0:
                print("⚠️  Low balance! Recommended: 5+ SOL for multiple deployments")
                print("💡 Fund with: Send SOL from exchange to above address")
            else:
                estimated_deployments = int(balance)
                print(f"✅ Sufficient for ~{estimated_deployments} token deployments")
        else:
            print("✅ Devnet wallet (free SOL available)")
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error checking wallet: {e}")

def show_wallet_management_help():
    """Show wallet management commands."""
    print(f"""
🔑 WALLET MANAGEMENT COMMANDS:

# Check funding wallet status
python3 ~/.scripts/check-funding-wallet.py

# Fund mainnet wallet (one-time setup)
# 1. Get address from above command
# 2. Send 5+ SOL from exchange
# 3. Ready for multiple token deployments

# Token-specific wallets are created automatically:
# ~/.solana-wallets/funding-mainnet.json    (your main funding wallet)
# ~/git/tokens/MOON-moon_finance/keypairs/  (token-specific wallets)

💡 RECOMMENDED SETUP:
1. Fund mainnet wallet once with 5+ SOL
2. Create unlimited tokens (1 SOL each)
3. Each token gets its own dedicated wallet
""")

def main():
    """Main wallet checking function."""
    print("🔑 Solana Funding Wallet Status")
    print("=" * 50)
    
    # Check both networks
    check_funding_wallet('devnet')
    check_funding_wallet('mainnet')
    
    show_wallet_management_help()

if __name__ == "__main__":
    main()
