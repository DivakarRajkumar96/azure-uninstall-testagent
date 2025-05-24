# azure-uninstall-testagent

This script leverages Azure Custom Script Extensions to automate post-deployment tasks on Azure Virtual Machines. Originally designed to uninstall **Test agents** from both Windows and Linux VMs. The script is fully generic and can be customized for a variety of post-provisioning operations such as software installation, patch management, log cleanup, or configuration changes all executed securely using Managed Identity.

# 🔧 Azure Automation Script – Remove Test Agent from VMs

This PowerShell script showcases how to utilize **Azure Automation** combined with **Managed Identity** to perform automated, post-deployment operations on Azure VMs. By harnessing Custom Script Extensions, it safely manages VM state (starting/stopping), removes any pre-existing conflicting extensions, and executes uninstall commands tailored to the VM’s OS type.

The current focus is on uninstalling **Test agents** from Azure VMs, but the approach and framework can be easily adapted to other automation workflows.

---

## 📘 What is Azure Automation?

**Azure Automation** is a cloud-native orchestration and configuration service that helps automate tasks across Azure and external environments. It supports runbooks for running complex workflows and integrates seamlessly with Managed Identities, removing the need to manage credentials manually.

---

## 🔐 Why Use Managed Identity?

Using **System-Assigned Managed Identity** for authentication enables this script to securely access Azure resources without embedding sensitive credentials. The Automation Account’s Managed Identity must be granted appropriate RBAC permissions, such as `Virtual Machine Contributor` and `Reader`, to manage VM power states and extensions.

---

## 📄 How to Use in Azure Automation

### 1. 🛠 Prerequisites

- An Azure Automation Account with a **System-Assigned Managed Identity** enabled  
- Import of the following Azure PowerShell modules into the Automation Account:  
  - `Az.Accounts`  
  - `Az.Compute`  

---

### 2. ➕ Import the Script as a Runbook

1. Navigate to your **Automation Account** in the Azure Portal  
2. Go to **Process Automation > Runbooks**  
3. Click **Create a Runbook**  
4. Enter:  
   - **Name**: `Remove-Test-Agent`  
   - **Runbook Type**: PowerShell  
5. Paste your PowerShell script (e.g., `uninstall-testagent.ps1`) into the editor and save  
6. Publish the runbook once ready  

---

### 3. 🔄 Assign Required Permissions

Ensure the Automation Account’s Managed Identity has permissions to:  
- Read VM details  
- Start and stop VMs  
- Manage VM extensions  

Grant the roles `Virtual Machine Contributor` and `Reader` at the resource group or VM scope accordingly.

---

### 4. ▶️ Execute the Script

- Start the runbook manually or schedule it as needed  
- Monitor job progress and output logs from the Automation Account's **Jobs** section  

---

## 🧪 Features

- Seamless authentication using Managed Identity  
- Graceful VM power state management (start if stopped, restore original state)  
- Removal of conflicting or prior Custom Script Extensions  
- OS-aware uninstall commands for Windows and Linux VMs  
- Cleanup and removal of temporary uninstall extensions after completion  

---

## 📌 Customization

Update the `$vmList` variable in the script with your own subscription IDs, resource groups, and VM names for targeted execution (note - the sciprt is using hardcoded values, in case if you want to dynamically include values, please integrate it with storage account):

```powershell
$vmList = @(  
    @{ Subscription = "SUB_ID"; VMName = "VM_NAME"; ResourceGroupName = "RG_NAME" }  
)

