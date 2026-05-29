#!/usr/bin/env python3
"""
Test script to validate token creation setup
"""

import os
import subprocess
import sys

def test_requirements():
    """Test if all requirements are met."""
    print("🔍 Testing token creation setup...")
    
    # Check if create-token script exists
    script_path = os.path.expanduser("~/.scripts/create-token")
    if not os.path.exists(script_path):
        print("❌ create-token script not found")
        return False
    
    if not os.access(script_path, os.X_OK):
        print("❌ create-token script is not executable")
        return False
    
    print("✅ create-token script exists and is executable")
    
    # Check if alias is configured
    try:
        result = subprocess.run(['zsh', '-c', 'alias token'], 
                               capture_output=True, text=True, check=True)
        if 'create-token' in result.stdout:
            print("✅ token alias is configured")
        else:
            print("❌ token alias not found or incorrect")
            return False
    except subprocess.CalledProcessError:
        print("❌ token alias not configured")
        return False
    
    # Test basic requirements
    requirements = ['git', 'rustc', 'cargo', 'node', 'npm', 'terraform', 'aws', 'solana']
    missing = []
    
    for req in requirements:
        try:
            subprocess.run([req, '--version'], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            missing.append(req)
    
    if missing:
        print(f"❌ Missing tools: {', '.join(missing)}")
        return False
    
    print("✅ All required tools are available")
    
    # Check credentials
    cred_issues = []
    
    # AWS credentials
    try:
        subprocess.run(['aws', 'sts', 'get-caller-identity'], 
                      capture_output=True, check=True)
        print("✅ AWS credentials configured")
    except subprocess.CalledProcessError:
        cred_issues.append("AWS credentials")
    
    # GitHub token
    if not os.getenv('GITHUB_ACCESS_TOKEN'):
        cred_issues.append("GITHUB_ACCESS_TOKEN")
    else:
        print("✅ GitHub token configured")
    
    if cred_issues:
        print(f"⚠️  Missing credentials: {', '.join(cred_issues)}")
        print("   These will be required for actual deployment")
    
    return len(missing) == 0

def main():
    """Main test function."""
    if test_requirements():
        print("\n🎉 Token creation setup is ready!")
        print("\nUsage: token SYMBOL domain.com")
        print("Example: token MOON moon.finance")
    else:
        print("\n❌ Setup incomplete. Please fix the issues above.")
        sys.exit(1)

if __name__ == "__main__":
    main()
