#!/usr/bin/env python3
"""
Global Token Creation Script
Creates a complete token website with Solana integration and AWS deployment.

Usage: token <TOKEN_SYMBOL> <DOMAIN_NAME>
Example: token MOON moon.finance
"""

import os
import sys
import subprocess
import json
import logging
import shutil
import tempfile
import venv
import atexit
from pathlib import Path
import urllib.request
import urllib.error
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(message)s'
)

# Template repository URL
TEMPLATE_REPO = "https://github.com/l3ocifer/sol-token.git"
TEMPLATE_DIR = os.path.expanduser("~/.token-template")

def print_banner():
    """Print the token creation banner."""
    print("""
╔══════════════════════════════════════════════════════════════╗
║                    🚀 TOKEN WEBSITE CREATOR                  ║
║                                                              ║
║  Creates complete Solana token ecosystem with payments      ║
║  • SPL Token Creation (devnet/mainnet)                      ║
║  • Professional React Website                               ║
║  • Dual Payments (Stripe + MoonPay)                         ║
║  • Automated Token Delivery                                 ║
║  • Admin Tools & DEX Integration                            ║
║  • AWS Infrastructure & Monitoring                          ║
╚══════════════════════════════════════════════════════════════╝
    """)

def check_requirements():
    """Check if all required tools are installed."""
    requirements = {
        'git': 'git --version',
        'rust': 'rustc --version',
        'cargo': 'cargo --version',
        'node': 'node --version',
        'npm': 'npm --version',
        'terraform': 'terraform --version',
        'aws': 'aws --version',
        'solana': 'solana --version'
    }
    
    missing = []
    for tool, command in requirements.items():
        try:
            subprocess.run(command.split(), capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            missing.append(tool)
    
    if missing:
        print(f"❌ Missing required tools: {', '.join(missing)}")
        print("\nPlease install the missing tools:")
        for tool in missing:
            if tool == 'rust':
                print("  • Rust: https://rustup.rs/")
            elif tool == 'node':
                print("  • Node.js: https://nodejs.org/")
            elif tool == 'terraform':
                print("  • Terraform: https://terraform.io/downloads")
            elif tool == 'aws':
                print("  • AWS CLI: https://aws.amazon.com/cli/")
            elif tool == 'solana':
                print("  • Solana CLI: https://docs.solana.com/cli/install-solana-cli-tools")
        sys.exit(1)
    
    print("✅ All required tools are installed")

def check_credentials():
    """Check if required credentials are configured."""
    missing_creds = []
    
    # Check AWS credentials
    try:
        subprocess.run(['aws', 'sts', 'get-caller-identity'], 
                      capture_output=True, check=True)
    except subprocess.CalledProcessError:
        missing_creds.append("AWS credentials")
    
    # Check GitHub token
    if not os.getenv('GITHUB_ACCESS_TOKEN'):
        missing_creds.append("GITHUB_ACCESS_TOKEN")
    
    if missing_creds:
        print(f"❌ Missing credentials: {', '.join(missing_creds)}")
        print("\nPlease configure:")
        if "AWS credentials" in missing_creds:
            print("  • AWS: Run 'aws configure' or set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY")
        if "GITHUB_ACCESS_TOKEN" in missing_creds:
            print("  • GitHub: Set GITHUB_ACCESS_TOKEN environment variable")
        sys.exit(1)
    
    print("✅ All credentials are configured")

def update_template():
    """Update or clone the template repository."""
    if os.path.exists(TEMPLATE_DIR):
        print("🔄 Updating template repository...")
        try:
            subprocess.run(['git', 'pull'], cwd=TEMPLATE_DIR, check=True, capture_output=True)
            print("✅ Template updated successfully")
        except subprocess.CalledProcessError:
            print("⚠️  Failed to update template, using existing version")
    else:
        print("📥 Cloning template repository...")
        try:
            subprocess.run(['git', 'clone', TEMPLATE_REPO, TEMPLATE_DIR], 
                          check=True, capture_output=True)
            print("✅ Template cloned successfully")
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to clone template: {e}")
            sys.exit(1)

def create_repo_name(token_symbol, domain_name):
    """Create repository name from token symbol and domain."""
    # Extract domain parts
    domain_parts = domain_name.split('.')
    if len(domain_parts) >= 2:
        domain_part = domain_parts[0]
        tld = '_'.join(domain_parts[1:])
        return f"{token_symbol.upper()}-{domain_part}_{tld}"
    else:
        return f"{token_symbol.upper()}-{domain_name}"

def create_github_repo(repo_name):
    """Create GitHub repository."""
    print(f"📝 Creating GitHub repository: {repo_name}")
    
    GITHUB_ACCESS_TOKEN = os.getenv('GITHUB_ACCESS_TOKEN')
    api_url = 'https://api.github.com/user/repos'
    headers = {
        'Authorization': f'token {GITHUB_ACCESS_TOKEN}',
        'Accept': 'application/vnd.github.v3+json'
    }
    data = json.dumps({
        'name': repo_name,
        'private': True,
        'description': f'Token website for {repo_name}',
        'auto_init': False
    }).encode('utf-8')
    
    req = urllib.request.Request(api_url, data=data, headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req) as response:
            if response.status == 201:
                print("✅ GitHub repository created")
            else:
                print(f"❌ Failed to create repository: {response.status}")
                sys.exit(1)
    except urllib.error.HTTPError as e:
        if e.code == 422:
            print("⚠️  Repository already exists, continuing...")
        else:
            print(f"❌ Failed to create repository: {e.code}")
            sys.exit(1)

def setup_project(repo_name, token_symbol, domain_name, token_name, network='devnet', dev_mode=False, tokenomics_preset='balanced', custom_supply=None, custom_price=None):
    """Set up the project directory and configuration."""
    project_dir = os.path.expanduser(f"~/git/tokens/{repo_name}")
    
    print(f"📁 Setting up project: {project_dir}")
    
    # Create project directory
    os.makedirs(project_dir, exist_ok=True)
    
    # Copy template files
    for item in os.listdir(TEMPLATE_DIR):
        if item not in ['.git', '__pycache__', 'target', 'node_modules', '.env']:
            src = os.path.join(TEMPLATE_DIR, item)
            dst = os.path.join(project_dir, item)
            if os.path.isdir(src):
                if os.path.exists(dst):
                    shutil.rmtree(dst)
                shutil.copytree(src, dst)
            else:
                shutil.copy2(src, dst)
    
    # Initialize git repository
    subprocess.run(['git', 'init'], cwd=project_dir, check=True)
    
    # Create environment configuration
    env_content = f"""# Token Website Configuration
# Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

# Domain Configuration
DOMAIN_NAME={domain_name}
REPO_NAME={repo_name}

# Token Information (will be updated by tokenomics configuration)
TOKEN_NAME={token_name}
TOKEN_SYMBOL={token_symbol}
TOKEN_DECIMALS=9
INITIAL_SUPPLY=100000000000
TOKEN_DESCRIPTION={token_name} - A revolutionary memecoin on Solana
TOKEN_PRICE_USD=0.0001
TOKENOMICS_PRESET={tokenomics_preset}
DEV_MODE={'true' if dev_mode else 'false'}"""
    
    # Add custom tokenomics if specified
    if custom_supply:
        env_content += f"\nCUSTOM_SUPPLY={custom_supply}"
    if custom_price:
        env_content += f"\nCUSTOM_PRICE={custom_price}"
    
    env_content += f"""

# Solana Configuration
RPC_URL=https://api.{network}.solana.com
SIGNER_KEYPAIR_PATH=./keypairs/payer.json

# Pinata Configuration (for metadata storage)
PINATA_JWT={os.getenv('PINATA_JWT', 'dev_mode_skip')}

# Payment Provider Configuration (dev mode uses placeholders)
STRIPE_SECRET_KEY={'dev_mode_skip' if dev_mode else os.getenv('STRIPE_SECRET_KEY', '')}
STRIPE_PUBLISHABLE_KEY={'dev_mode_skip' if dev_mode else os.getenv('STRIPE_PUBLISHABLE_KEY', '')}
MOONPAY_API_KEY={'dev_mode_skip' if dev_mode else os.getenv('MOONPAY_API_KEY', '')}

# AWS Configuration
AWS_ACCESS_KEY_ID={os.getenv('AWS_ACCESS_KEY_ID', '')}
AWS_SECRET_ACCESS_KEY={os.getenv('AWS_SECRET_ACCESS_KEY', '')}
AWS_DEFAULT_REGION=us-east-1

# GitHub Configuration
GITHUB_ACCESS_TOKEN={os.getenv('GITHUB_ACCESS_TOKEN', '')}
"""
    
    with open(os.path.join(project_dir, '.env'), 'w') as f:
        f.write(env_content)
    
    # Create website configuration
    website_config = {
        "domain": domain_name,
        "token": {
            "name": token_name,
            "symbol": token_symbol,
            "description": f"{token_name} - A revolutionary token on Solana",
            "decimals": 9,
            "initial_supply": 1000000000
        },
        "features": {
            "wallet_connection": True,
            "token_purchase": True,
            "token_info_display": True,
            "social_links": {}
        }
    }
    
    with open(os.path.join(project_dir, 'website-config.json'), 'w') as f:
        json.dump(website_config, f, indent=2)
    
    # Set up git remote (idempotent)
    origin_url = f'git@github.com:l3ocifer/{repo_name}.git'
    try:
        subprocess.run(['git', 'remote', 'add', 'origin', origin_url], cwd=project_dir, check=True)
    except subprocess.CalledProcessError:
        # Remote already exists, update it
        subprocess.run(['git', 'remote', 'set-url', 'origin', origin_url], cwd=project_dir, check=True)
        print("✅ Git remote updated")
    
    print("✅ Project setup complete")
    return project_dir

def get_or_create_funding_wallet(network):
    """Get or create the main funding wallet for the specified network."""
    funding_wallet_dir = os.path.expanduser('~/.solana-wallets')
    os.makedirs(funding_wallet_dir, exist_ok=True)
    
    funding_wallet_path = os.path.join(funding_wallet_dir, f'funding-{network}.json')
    
    if not os.path.exists(funding_wallet_path):
        print(f"🔑 Creating funding wallet for {network.upper()}...")
        subprocess.run(['solana-keygen', 'new', '--outfile', funding_wallet_path, '--no-bip39-passphrase'], 
                      check=True, input='\n', text=True)
        
        # Get wallet address for funding instructions
        result = subprocess.run(['solana-keygen', 'pubkey', funding_wallet_path], 
                               capture_output=True, text=True, check=True)
        funding_address = result.stdout.strip()
        
        if network == 'mainnet':
            print(f"💰 FUNDING REQUIRED: Send SOL to your funding wallet")
            print(f"   Wallet Address: {funding_address}")
            print(f"   Recommended: 5+ SOL (for multiple token creations)")
            print(f"   • Send from exchange (Coinbase, Binance, etc.)")
            print(f"   • Save this address for future token creations")
            input("\nPress Enter after funding the wallet...")
        else:
            print(f"✅ Devnet funding wallet created: {funding_address}")
    
    return funding_wallet_path

def create_admin_wallet(project_dir, token_symbol, network='devnet'):
    """Create or verify token-specific admin wallet with proper naming."""
    print(f"👤 Setting up admin wallet for {token_symbol}...")
    
    keypairs_dir = os.path.join(project_dir, 'keypairs')
    os.makedirs(keypairs_dir, exist_ok=True)
    
    # Create token-specific wallet with proper naming
    wallet_name = f"{token_symbol.lower()}-admin-{network}"
    payer_keypair = os.path.join(keypairs_dir, 'payer.json')
    descriptive_keypair = os.path.join(keypairs_dir, f'{wallet_name}.json')
    
    # Check if wallet already exists
    if os.path.exists(payer_keypair):
        print(f"🔍 Found existing wallet for {token_symbol}")
        
        # Get existing wallet address
        result = subprocess.run(['solana-keygen', 'pubkey', payer_keypair], 
                               capture_output=True, text=True, check=True)
        wallet_address = result.stdout.strip()
        print(f"   Address: {wallet_address}")
        
        # Ensure descriptive copy exists
        if not os.path.exists(descriptive_keypair):
            subprocess.run(['cp', payer_keypair, descriptive_keypair], check=True)
            print(f"✅ Created descriptive copy: {wallet_name}.json")
        
    else:
        print(f"🔑 Creating new wallet: {wallet_name}")
        
        # Generate keypair
        subprocess.run(['solana-keygen', 'new', '--outfile', payer_keypair, '--no-bip39-passphrase'], 
                      check=True, input='\n', text=True)
        
        # Copy to descriptive name
        subprocess.run(['cp', payer_keypair, descriptive_keypair], check=True)
        
        # Get wallet address
        result = subprocess.run(['solana-keygen', 'pubkey', payer_keypair], 
                               capture_output=True, text=True, check=True)
        wallet_address = result.stdout.strip()
        
        print(f"✅ Created wallet: {wallet_name}")
        print(f"   Address: {wallet_address}")
    
    # Handle wallet funding based on network
    print(f"💰 Funding {token_symbol} admin wallet on {network.upper()}...")
    
    rpc_url = f'https://api.{network}.solana.com' if network == 'devnet' else 'https://api.mainnet-beta.solana.com'
    
    try:
        balance_result = subprocess.run(['solana', 'balance', wallet_address, '--url', network if network == 'devnet' else 'mainnet-beta'], 
                                      capture_output=True, text=True, check=True)
        balance = float(balance_result.stdout.split()[0])
        
        if network == 'devnet':
            if balance < 0.1:
                print(f"💰 Funding devnet wallet: {wallet_address}")
                subprocess.run(['solana', 'airdrop', '2', wallet_address, '--url', 'devnet'], check=True)
                print("✅ Devnet wallet funded with 2 SOL")
            else:
                print(f"✅ Devnet wallet already funded: {balance} SOL")
        else:  # mainnet
            if balance < 0.1:
                # Need to fund from main funding wallet
                funding_wallet_path = get_or_create_funding_wallet('mainnet')
                
                print(f"🔄 Funding from main wallet...")
                try:
                    # Transfer 1 SOL from funding wallet to token wallet
                    subprocess.run([
                        'solana', 'transfer', '1', wallet_address,
                        '--keypair', funding_wallet_path,
                        '--url', 'mainnet-beta'
                    ], check=True)
                    print(f"✅ Transferred 1 SOL to {token_symbol} admin wallet")
                except subprocess.CalledProcessError as e:
                    print(f"❌ Failed to transfer SOL: {e}")
                    print(f"💰 Manually fund wallet: {wallet_address}")
                    print("   • Send 0.1+ SOL from exchange or existing wallet")
                    sys.exit(1)
            else:
                print(f"✅ Mainnet wallet already funded: {balance} SOL")
                
    except subprocess.CalledProcessError:
        if network == 'devnet':
            print("💰 Attempting to fund devnet wallet...")
            try:
                subprocess.run(['solana', 'airdrop', '2', wallet_address, '--url', 'devnet'], check=True)
                print("✅ Devnet wallet funded with 2 SOL")
            except subprocess.CalledProcessError:
                print("❌ Failed to fund devnet wallet. Check Solana CLI setup.")
                sys.exit(1)
        else:
            print("⚠️  Could not check mainnet wallet balance")
            print("❗ Ensure wallet has at least 0.1 SOL for token creation")
    
    print(f"✅ Admin wallet created: {wallet_address}")
    return wallet_address

def deploy_project(project_dir):
    """Deploy the complete project."""
    print("🚀 Deploying project...")
    
    # Change to project directory
    original_dir = os.getcwd()
    os.chdir(project_dir)
    
    try:
        # Run deployment script (it handles its own virtual environment)
        subprocess.run(['python3', 'scripts/deployment/deploy.py'], check=True)
        print("✅ Project deployed successfully")
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Deployment failed: {e}")
        print("📋 Check logs in logs/ directory for details")
        return False
    finally:
        os.chdir(original_dir)
    
    return True

def display_results(repo_name, domain_name, wallet_address, project_dir, network='devnet'):
    """Display final results and information."""
    print(f"""
╔══════════════════════════════════════════════════════════════╗
║                    🎉 DEPLOYMENT COMPLETE!                   ║
╚══════════════════════════════════════════════════════════════╝

🌐 Website URL: https://{domain_name}
📁 Project Directory: {project_dir}
👤 Admin Wallet: {wallet_address}
📦 GitHub Repository: https://github.com/l3ocifer/{repo_name}

💳 PAYMENT METHODS ACTIVE:
• Stripe: Credit/debit cards, Apple Pay, Google Pay
• MoonPay: Crypto payments, bank transfers

🪙 TOKENOMICS CONFIGURED:
• 100B total supply (memecoin standard)
• $0.0001 per token (great psychological price)
• 85B tokens in admin wallet
• 15B tokens reserved for liquidity

📋 NEXT STEPS:
1. Visit your website: https://{domain_name}
2. Test wallet connection and token purchases
3. Monitor purchases: AWS CloudWatch dashboard
4. Set up DEX trading: python3 admin/setup-dex.py

⚠️  IMPORTANT:
• Backup your admin wallet: {project_dir}/keypairs/payer.json
• Token deployed on SOLANA {network.upper()}
• For LIVE payments: Get Stripe/MoonPay business approval
• Currently using TEST payment keys (no real money processed)

🔧 MANAGE YOUR TOKEN:
cd {project_dir}
python3 admin/token-admin.py info      # Check token status
python3 admin/token-admin.py send      # Send tokens
python3 admin/setup-dex.py             # Create liquidity pools
python3 create-token-website.py        # Redeploy after changes
""")

def create_venv():
    """Create a virtual environment for Python dependencies."""
    venv_path = os.path.expanduser('~/.token_creator_venv')
    if not os.path.exists(venv_path):
        print("📦 Creating virtual environment...")
        try:
            venv.create(venv_path, with_pip=True)
            print("✅ Virtual environment created")
        except Exception as e:
            print(f"❌ Failed to create virtual environment: {e}")
            raise
    return venv_path

def install_dependencies(venv_path):
    """Install required Python dependencies in virtual environment."""
    print("📦 Installing Python dependencies...")
    
    if sys.platform == 'win32':
        pip_executable = os.path.join(venv_path, 'Scripts', 'pip')
        python_executable = os.path.join(venv_path, 'Scripts', 'python.exe')
    else:
        pip_executable = os.path.join(venv_path, 'bin', 'pip')
        python_executable = os.path.join(venv_path, 'bin', 'python')
    
    required_packages = [
        'python-dotenv',
        'boto3>=1.34.0',
        'botocore>=1.34.0',
        'requests'
    ]
    
    for package in required_packages:
        try:
            subprocess.run([pip_executable, 'install', package], check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to install {package}: {e}")
            raise
    
    print("✅ Dependencies installed")
    return python_executable

def cleanup_venv(venv_path):
    """Clean up virtual environment."""
    if os.path.exists(venv_path):
        print("🧹 Cleaning up virtual environment...")
        shutil.rmtree(venv_path)

def main():
    """Main function for token creation with venv management."""
    # Check if we're running in virtual environment
    if '--venv-activated' not in sys.argv:
        print_banner()
        
        # Create and activate virtual environment
        venv_path = create_venv()
        atexit.register(cleanup_venv, venv_path)
        
        try:
            python_executable = install_dependencies(venv_path)
            
            # Re-invoke script in virtual environment
            print("🔄 Re-running in virtual environment...")
            subprocess.run([python_executable, __file__, *sys.argv[1:], '--venv-activated'], check=True)
            
        except Exception as e:
            print(f"❌ Virtual environment setup failed: {e}")
            raise
        finally:
            cleanup_venv(venv_path)
        
        return
    
    # We're now running in the virtual environment
    print_banner()
    
    # Parse arguments (remove the venv flag)
    args = [arg for arg in sys.argv[1:] if arg != '--venv-activated']
    
    if len(args) < 2:
        print("Usage: token <TOKEN_SYMBOL> <DOMAIN_NAME> [options]")
        print("Example: token MOON moon.finance")
        print("Options:")
        print("  --network=devnet|mainnet        # Default: devnet (for testing)")
        print("  --dev                           # Dev mode: no payment providers required")
        print("  --tokenomics=conservative|balanced|aggressive")
        print("  --supply=100000000000")
        print("  --price=0.0001")
        print("  --name='Custom Token Name'")
        print("\nExamples:")
        print("  token TESTCOIN test.domain.com --dev              # Dev mode testing")
        print("  token MOON moon.finance --network=mainnet         # Production")
        sys.exit(1)
    
    token_symbol = args[0].upper()
    domain_name = args[1].lower()
    
    # Parse optional arguments
    network = 'devnet'  # Default to devnet for safe testing
    dev_mode = False    # Dev mode bypasses payment providers
    tokenomics_preset = 'balanced'  # Default
    custom_supply = None
    custom_price = None
    custom_name = None
    
    for arg in args[2:]:
        if arg.startswith('--network='):
            network = arg.split('=')[1].lower()
            if network not in ['devnet', 'mainnet']:
                print("❌ Invalid network. Use 'devnet' or 'mainnet'")
                sys.exit(1)
        elif arg == '--dev':
            dev_mode = True
            print("🔧 DEV MODE: Payment providers will be skipped")
        elif arg.startswith('--tokenomics='):
            tokenomics_preset = arg.split('=')[1]
        elif arg.startswith('--supply='):
            custom_supply = int(arg.split('=')[1])
        elif arg.startswith('--price='):
            custom_price = float(arg.split('=')[1])
        elif arg.startswith('--name='):
            custom_name = arg.split('=')[1].strip("'\"")
    
    if custom_name:
        token_name = custom_name
    else:
        try:
            token_name = input(f"Enter full token name (default: {token_symbol} Token): ").strip() or f"{token_symbol} Token"
        except EOFError:
            # Non-interactive environment, use default
            token_name = f"{token_symbol} Token"
    
    print(f"Creating token: {token_name} ({token_symbol})")
    print(f"Domain: {domain_name}")
    print(f"Network: {network.upper()}")
    print(f"Tokenomics: {tokenomics_preset}")
    if dev_mode:
        print("Mode: DEVELOPMENT (no payment providers)")
    print()
    
    # Check requirements and credentials
    check_requirements()
    check_credentials()
    
    # Update template
    update_template()
    
    # Create repository name
    repo_name = create_repo_name(token_symbol, domain_name)
    
    # Create GitHub repository
    create_github_repo(repo_name)
    
    # Set up project with tokenomics and network options
    project_dir = setup_project(repo_name, token_symbol, domain_name, token_name, network, dev_mode, tokenomics_preset, custom_supply, custom_price)
    
    # Create admin wallet
    wallet_address = create_admin_wallet(project_dir, token_symbol, network)
    
    # Deploy project
    if deploy_project(project_dir):
        display_results(repo_name, domain_name, wallet_address, project_dir, network)
    else:
        print("❌ Deployment failed. Check the logs above for details.")
        sys.exit(1)

if __name__ == "__main__":
    main()
