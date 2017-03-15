<#
.SYNOPSIS
Call this module to utilize functions for VMWare deployments.

.DESCRIPTION
Module prepared for automated deployments of Resource Pool, 4 port groups on different VLANs, pfSense router, and permissions assign.  Contact kyle.vidmar@gmail.com for questions.

.EXAMPLE
PS > within PowerCLI scripts call .\VMWare_Deploy.ps1

.LINK
https://github.com/kylevidmar/vmware_deploy/

.NOTES
Last modified 3/15/17
#>

<####################################
 # Constants
 ####################################>
 
$vCenter = ""
#vCenter DNS or IP
$User_Resource_Pool_Prefix = ""
#This is the prefix before the numeric identifier of the Resource Pool (Example: ABCD would deploy sequential resource pools starting ABCD001, ABCD002, etc)
$dvSwitchName = ""
#dvSwitch in VMware to use, it will create port groups on this switch
$Digits_In_Numeric_Identifier = 3
#This is how many digits after the prefix are part of the numberic identifier (Example: CLMM### is 3, thus supports 999)
$Users_Resource_Pool = ""
#Resource Pool to create sub Resource Pools in for individual users
$Groups_Resource_Pool = ""
#Resource pool where group resource pools are stored, group resource pools support multiple users assigned to them
$Users_Folder = "Users"
#Logical side but same as above
$Groups_Folder = "Groups"
#Logical side but same as above
$Routers_Resource_Pool = ""
#Resource pool for pfSense routers to deploy to
$Router_Folder = "Routers"
#Folder for Routers

$Credential_File_Location = "/CredentialFiles/"
#If you want to auth with credential file update this path accordingly


$SMTP_Server = "1.2.3.4"
#Notifications to users occurs after deployment using this SMTP server
$SMTP_From = "you@you.com"
#From SMTP
$Message_Body_Default = "You can access the vCenter for your Resource Pool at 443`n`nUse your domain credentials to log in. "
#Get-VIRole created roles for specific VI devices
$GCP_Datacenter = ""
#Top level datacenter to deploy to, (GCP=general compute platform, ignore the term it is throughout the entire script was a big buzz word during scripting)

$Resource_Pool_Role = ""
#Role you want for RPs, you create the roles in the permissions of vmware
$VM_Folder_Role = ""
#Role you want for folders
$VM_Network_Role = ""
#Role you want for VM Networks

#Datastore cluster deployments are only supported in vCenter 5.5+ so make sure your environment supports this otherwise use a datastore naming convention and the Get_Datastore function
$Datastore_Cluster = ""
#Datastore cluster to deploy to
$Datastore_Naming_Prefix = ""
#If you don't have a datastore cluster and want to calculate based on several datastores, i.e deploy to datastore with most free space, you can use this option if they follow a similar naming convention
$Router_Template = ""
#Name of pfSense router template
$Router_Name = "vRouter"
#This will be appended to the User_Resource_Pool_Prefix (Example: ABCD001-vRouter) for the pfSense deployment and placed in the Router Resource Pool
$Jump_VLAN = ""
#Port group the vRouter sits on for external access
$Domain = "COSTCO\"
#Domain of environment with \ after
$Domain_com = "Costco.com"
#For sending to $Username@x.com notifications

$Management_PortGroup_ID = "MGMT" 
#The identifier used after the User_Resource_Pool_Prefix in the port group name to specify management (Example: ABCD001-MGMT-1006 is MGMT)
$A_PortGroup_ID = "A" 
#The identifier used after the User_Resource_Pool_Prefix in the port group name to specify management (Example: ABCD001-A-1501 is A)
$B_PortGroup_ID = "B" 
#The identifier used after the User_Resource_Pool_Prefix in the port group name to specify management (Example: ABCD001-B-1502 is B)
$C_PortGroup_ID = "C" 
#The identifier used after the User_Resource_Pool_Prefix in the port group name to specify management (Example: ABCD001-C-1503 is C)
$D_PortGroup_ID = "D" 
#The identifier used after the User_Resource_Pool_Prefix in the port group name to specify management (Example: ABCD001-D-1504 is D)
$Group_VLAN_Start = "3000"
#Start VLAN for Group Resource Pools, since they use a different subset of predetermined VLANs in my POC
$MGMT_Start = "1000"
#Start VLAN for MGMT Port Groups, in our environment they wanted MGMT traffic on a different subset than A/B/C/D VLAN traffic so we can monitor differently, thus these vars
$Individual_Start = "1500"
#Start VLAN for A/B/C/D Port Groups, A would start at VLAN 1500, B 1501, C 1502, etc

<####################################
 # Main
 ####################################>

 function Create_Cred_File
{
<#
.SYNOPSIS
Creates a reusable hash credential file for a specific user.

.DESCRIPTION
Use the credential file to connect to VMWare to run PowerCLI commands.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER username
Domain Username

.PARAMETER password
Domain Password

.EXAMPLE
PS > Create_Cred_File
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$username,
    [Parameter(Position = 1, Mandatory = $False, Parametersetname="Exfil")] [String]$password)

if ($Username.Startswith($Domain) -eq $false){
$Username = "$Domain$Username"
}
$CredFileName = $Username.TrimStart("$Domain")
$CredFile = $Credential_File_Location + $CredFileName + ".xml"

New-VICredentialStoreItem -Host $vCenter -User $Username -Password $Password -File $CredFile

}

#############################################################################################

function Connect_To_GCP
{
<#
.SYNOPSIS
Connect to VMWare.

.DESCRIPTION
Use the username and password provided to connect to VMWare to run PowerCLI commands.  Also accepts a credential file path.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER username
Domain username.

.PARAMETER password
Domain password.

.EXAMPLE
PS > Connect_To_GCP <username> <optional password>
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$username,
    [Parameter(Position = 1, Mandatory = $False, Parametersetname="Exfil")] [String]$password)

if ($username.Endswith(".xml")){
    Write-Host "`nUsing credential file $username...`n"
    if ($username.startswith($Credential_File_Location) -eq $false){$username = $Credential_File_Location + $username
        Write-Host "Using $username credential file...`n"
    }
    $creds = Get-VICredentialStoreItem -file $username
    Connect-viserver -Server $creds.Host -User $creds.User -Password $creds.Password 
}

else{
if ($Username.Startswith("$Domain") -eq $false){
$Username = "$Domain$Username"
}
if ($password -eq ""){
Connect-VIServer -server $vCenter -credential (Get-Credential)
}
if ($password -ne ""){
Connect-VIServer -server $vCenter -user $username -pass $password
}
}
}

#############################################################################################

function Find_Next_Resource_Pool_Number
{
<#
.SYNOPSIS
Finds the next number to be used in Resource Pool.

.DESCRIPTION
Naming mechanism for Resource Pools uses a 3 digit number after the prefix.  This will find the next available 3 digit number

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.EXAMPLE
PS > Find_Next_Resource_Pool_Number
#>

$Resource_Pools = @()
#Create empty array
$Resource_Pools = Get-ResourcePool -Location $Users_Resource_Pool | foreach{[int]($_.name).trimstart($User_Resource_Pool_Prefix).substring(0,$Digits_In_Numeric_Identifier)}
#Get the current resource pools and cut off the prefix and just get the number identifier as an integer
$Resource_Pools = $Resource_Pools | sort
#Sort them numberically
$Next_Resource_Pool_Number = $Resource_Pools[0]
#Start with the first number
do {$Next_Resource_Pool_Number += 1}
until ($Resource_Pools -notcontains $Next_Resource_Pool_Number)
#Add 1 to the first number used then compare to array of in use number until lowest available is found
$Next_Resource_Pool_Number = "{0:D$Digits_In_Numeric_Identifier}" -f $Next_Resource_Pool_Number
#Convert to a however many digit number as specified in constant variables
return $Next_Resource_Pool_Number
}

#############################################################################################

function Create_Resource_Pool_and_Folder
{
<#
.SYNOPSIS
Create a Resource Pool and Folder.

.DESCRIPTION
Create a Resource Pool and Folder in vCenter for the specified user.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Username
Domain username of the user you are creating the pod for.

.EXAMPLE
PS > Create_Resource_Pool <username>
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Username)

$Resource_Pool_Number = Find_Next_Resource_Pool_Number
$Resource_Pool = "$User_Resource_Pool_Prefix$Resource_Pool_Number - $Username"
$Folder = "$User_Resource_Pool_Prefix$Resource_Pool_Number - $Username"
Write-Color -Text "STATUS: ","Creating Resource Pool ","$Resource_Pool"," now..." -Color Cyan,Gray,Yellow,Gray
$null = New-ResourcePool -Location $Users_Resource_Pool -Name $Resource_Pool
Write-Color -Text "STATUS: ","Creating Folder ","$Folder"," now..." -Color Cyan,Gray,Yellow,Gray
$null = New-Folder -Location $Users_Folder -Name $Folder
$Username = "$Domain$Username"
Set_Resource_Pool_Permissions $Resource_Pool $Username
Set_Folder_Permissions $Folder $Username
Deploy_Router_To_Resource_Pool $Resource_Pool $Username
Notify_User $Username $Resource_Pool
}

#############################################################################################

function Set_Folder_Permissions
{
<#
.SYNOPSIS
Changes permissions on VI entity.

.DESCRIPTION
Will set the default role sepcified in constants for the entity type and name provided to user provided.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER entity
VI Name of the entity you want to change permissions on

.PARAMETER username
Domain username of the user you want to grant permissions.

.EXAMPLE


#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Entity,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Username)

Write-Color -Text "STATUS: ","Setting Folder permissions for ","$Entity ", "to", " $Username"," now..." -Color Cyan,Gray,Yellow,Gray,Yellow,Gray
$null = New-VIPermission -Entity (Get-Folder $Entity) -Principal $Username -Role $VM_Folder_Role

}

#############################################################################################

function Set_Resource_Pool_Permissions
{
<#
.SYNOPSIS
Changes permissions on VI entity.

.DESCRIPTION
Will set the default role sepcified in constants for the entity type and name provided to user provided.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER entity
VI Name of the entity you want to change permissions on

.PARAMETER username
Domain username of the user you want to grant permissions.

.EXAMPLE
PS > Set_Resource_Pool_Permissions "ABCD001 - jsmith" "COSTCO\jsmith"
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Entity,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Username)

Write-Color -Text "STATUS: ","Setting Resource Pool permissions for ","$Entity ", "to", " $Username"," now..." -Color Cyan,Gray,Yellow,Gray,Yellow,Gray
$null = New-VIPermission -Entity (Get-ResourcePool $Entity) -Principal $Username -Role $Resource_Pool_Role

}

#############################################################################################

function Set_VM_Permissions
{
<#
.SYNOPSIS
Changes permissions on VI entity.

.DESCRIPTION
Will set the default role sepcified in constants for the entity type and name provided to user provided.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER entity
VI Name of the entity you want to change permissions on

.PARAMETER username
Domain username of the user you want to grant permissions.

.EXAMPLE
PS > Set_VM_Permissions "Ubuntu14.4-smcmulle" "COSTCO\jsmith"
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Entity,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Username)

Write-Color -Text "STATUS: ","Setting VM permissions for ","$Entity ", "to", " $Username"," now..." -Color Cyan,Gray,Yellow,Gray,Yellow,Gray
$null = New-VIPermission -Entity (Get-VM $Entity) -Principal $Username -Role $VM_Folder_Role

}

#############################################################################################

function Set_Router_Permissions
{
<#
.SYNOPSIS
Changes permissions on VI entity.

.DESCRIPTION
Will set the default role sepcified in constants for the entity type and name provided to user provided.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER entity
VI Name of the entity you want to change permissions on

.PARAMETER username
Domain username of the user you want to grant permissions.

.EXAMPLE
PS > Set_Router_Permissions "ABCD001 - jsmith" "COSTCO\jsmith"
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Entity,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Username)

$Resource_Pool_Prefix = Get_Resource_Pool_Prefix $Entity
$Management_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$Management_PortGroup_ID-*"
$A_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$A_PortGroup_ID-*"
$B_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$B_PortGroup_ID-*"
$C_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$C_PortGroup_ID-*"
$D_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$D_PortGroup_ID-*"

Write-Color -Text "STATUS: ","Setting permissions for the port groups for ","$Entity ", "to", " $Username"," now..." -Color Cyan,Gray,Yellow,Gray,Yellow,Gray

$null = New-VIPermission -Entity $Management_Interface -Principal $Username -Role $VM_Network_Role
$null = New-VIPermission -Entity $A_Interface -Principal $Username -Role $VM_Network_Role
$null = New-VIPermission -Entity $B_Interface -Principal $Username -Role $VM_Network_Role
$null = New-VIPermission -Entity $C_Interface -Principal $Username -Role $VM_Network_Role
$null = New-VIPermission -Entity $D_Interface -Principal $Username -Role $VM_Network_Role
}

#############################################################################################

function Get_Datastore
{
<#
.SYNOPSIS
Returns available datastore.

.DESCRIPTION
Looks at datastore statistics and returns datastore with most available space based on Datastore_Naming_Prefix constant variable.  
This function will be obsolete when vCenter 5.5 is available and Datastore clusters work for deployments.

.EXAMPLE
PS > Get_Datastore
#>

$Largest = 0.0
$Datastore = @()
foreach ($Datastore in (Get-DatastoreCluster -name $Datastore_Cluster | Get-Datastore | Select Name, FreeSpaceMB)) {
    if($Datastore.FreeSpaceMB -ge $Largest) {
        $Largest = $Datastore.FreeSpaceMB
        $Datastore_To_Use = $Datastore.Name
    }
}
return $Datastore_To_Use
}

#############################################################################################

function Get_Resource_Pool_Prefix
{
<#
.SYNOPSIS
Returns a prefix for VM names.

.DESCRIPTION
Uses the length of the resource pool prefix and characters in the unique identifier to trim the resource pool name down.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Resource_Pool
Name of Resource_Pool object.

.EXAMPLE
PS > Get_Resource_Pool_Prefix "ABCD001 - jsmith"
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool)

#This function is primarily used in VM_Name creation, it will append this resource pool prefix to the VM name
$Characters_To_Trim = ($User_Resource_Pool_Prefix.Length) + $Digits_In_Numeric_Identifier
$Resource_Pool_Prefix = $Resource_Pool.substring(0,$Characters_To_Trim)
return $Resource_Pool_Prefix
}

#############################################################################################

function Get_Username_From_Resource_Pool
{
<#
.SYNOPSIS
Returns a username from a resource pool.

.DESCRIPTION
Takes the resource pool name and chops it to just the username.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Resource_Pool
Name of Resource_Pool object.

.EXAMPLE
PS > Get_Username_From_Resource_Pool "ABCD001 - jsmith"
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool)

#This function is primarily used in VM_Name creation, it will append this resource pool prefix to the VM name
$Characters_To_Trim = ($User_Resource_Pool_Prefix.Length) + $Digits_In_Numeric_Identifier + 3
#The three comes from the " - " in between ABCD001 and the username
$Username = $Resource_Pool.substring($Characters_To_Trim)
return $Username
}

#############################################################################################

function Deploy_Template_To_Resource_Pool
{
<#
.SYNOPSIS
Deploys a template to an available resource pool.

.DESCRIPTION
Takes template provided and deploys it to the resource pool provided.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Template
Name of Template object.

.PARAMETER Resource_Pool
Name of Resource Pool object.

.EXAMPLE
PS > Deploy_Template_To_Resource_Pool "Ubuntu_Template" "ABCD001 - jsmith"
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Template,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool)

#Find datastore with most free space
$Datastore = Get_Datastore
$Datastore = Get-Datastore -Location $GCP_Datacenter -name $Datastore
#Get resource pool prefix to append to the VM_Name
$Resource_Pool_Prefix = Get_Resource_Pool_Prefix $Resource_Pool
#See if resource pool already has this item if it does append a number to the end of the object name
$Resource_Pool_Contents = Get-VM -Location $Resource_Pool | foreach{$_.name}
$VM_Name = "$Resource_Pool_Prefix-$Template"
if ($Resource_Pool_Contents -contains $VM_Name){
$i = 1
do {$i+=1;$VM_Name = "$VM_Name-$i"}
until ($Resource_Pool_Contents -notcontains $VM_Name)
}
Write-Color -Text "STATUS: ","Deploying template ","$Template ", "to", " $Resource_Pool"," now..." -Color Cyan,Gray,Yellow,Gray,Yellow,Gray
#Create the VM now that a name has been decided for the object
$null = New-VM -Location (Get-Folder $Resource_Pool) -Template $Template -Datastore $Datastore -Name $VM_Name -ResourcePool $Resource_Pool -ErrorAction "SilentlyContinue"
Start-Sleep -s 10
$Username = Get_Username_From_Resource_Pool $Resource_Pool
$Username = "$Domain$Username"
Set_VM_Permissions $VM_Name $Username
Write-Color -Text "STATUS: ","Powering on ","$VM_Name ","now..." -Color Cyan,Gray,Yellow,Gray
$null = Start-VM $VM_Name -Confirm:$false
}

#############################################################################################

function Deploy_Router_To_Resource_Pool
{
<#
.SYNOPSIS
Deploys a router to an available resource pool.

.DESCRIPTION
Takes router template provided in constant and deploys it to the resource pool provided.  It will still logically place it in the Router Resource Pool but it uses the name to get the interfaces required.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Resource_Pool
Name of Resource Pool object.

.PARAMETER Username
Domain Username.

.EXAMPLE
PS > Deploy_Router_To_Resource_Pool "ABCD001 - jsmith" "jsmith"
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Username)

#Find datastore with most free space
$Datastore = Get_Datastore
$Datastore = Get-Datastore -Location $GCP_Datacenter -name $Datastore
#Get resource pool prefix to append to the VM_Name
$Resource_Pool_Prefix = Get_Resource_Pool_Prefix $Resource_Pool
#See if resource pool for routers already has this one in it
$Resource_Pool_Contents = Get-VM -Location $Routers_Resource_Pool | foreach{$_.name}
$VM_Name = "$Resource_Pool_Prefix-$Router_Name"
if ($Resource_Pool_Contents -contains $VM_Name){
Write-Host "Router already exists for Resource Pool $Resource_Pool"
}
#Checking for port groups
Write-Color -Text "STATUS: ","Checking for port groups now..." -Color Cyan,Gray
Create_Individual_Port_Groups $Resource_Pool_Prefix
#Create the VM now that a name has been decided for the object
Write-Color -Text "STATUS: ","Deploying router for resource pool ","$Resource_Pool"," now..." -Color Cyan,Gray,Yellow,Gray
$null = New-VM -Location (Get-Folder $Router_Folder) -Template $Router_Template -Datastore $Datastore -Name $VM_Name -ResourcePool $Routers_Resource_Pool -ErrorAction "SilentlyContinue"
Start-Sleep -s 10
Write-Color -Text "STATUS: ","Placing eth0 for vRouter to ","$Jump_VLAN"," now..." -Color Cyan,Gray,Yellow,Gray
$null = Get-VM $VM_Name | Get-NetworkAdapter -name "Network adapter 1" | Set-NetworkAdapter -NetworkName $Jump_VLAN -Confirm:$false
$Internal_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$Management_PortGroup_ID-*"
Write-Color -Text "STATUS: ","Placing eth1 for vRouter to ","$Internal_Interface"," now..." -Color Cyan,Gray,Yellow,Gray
$null = Get-VM $VM_Name | Get-NetworkAdapter -name "Network adapter 2" | Set-NetworkAdapter -NetworkName $Internal_Interface -Confirm:$false
Write-Color -Text "STATUS: ","Powering on ","$VM_Name", " now..." -Color Cyan,Gray,Yellow,Gray
$null = Start-VM $VM_Name -Confirm:$false
Set_Router_Permissions $Resource_Pool $Username
}

#############################################################################################

function Clean_Up_Leftover_Pods
{
<#
.SYNOPSIS
Looks through the Pods to see if any are ready to be deleted.

.DESCRIPTION
Cross references Resource Pool/Folders to see if any should be purged.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.EXAMPLE
PS > Clean_Up_Leftover_Pods
#>

$Resource_Pools = @()
#Create empty array
$Folders = @()
#Create empty array
$Resource_Pools_Without_Folders = @()
#Create empty array

$Resource_Pools = Get-ResourcePool -Location $Users_Resource_Pool | foreach{$_.name}
$Folders = Get-Folder -Location $Users_Folder | foreach{$_.name}

foreach($Resource_Pool in $Resource_Pools){
if ($Folders -notcontains $Resource_Pool){
$Resource_Pools_Without_Folders += $Resource_Pool
}
}
$Resource_Pools = @()
#Create empty array
$Resource_Pools_Without_VMs = @()
#Create empty array

$Resource_Pools = Get-ResourcePool -Location $Users_Resource_Pool | foreach{$_.name}

foreach($Resource_Pool in $Resource_Pools){
if ((Get-ResourcePool -name $Resource_Pool | Get-VM | foreach{$_.name}) -eq $null){
$Resource_Pools_Without_VMs += $Resource_Pool
}
}
Write-Host "Resource Pools without Folders assigned to them: `n" $Resource_Pools_Without_Folders
Write-Host "Resource Pools without VMs in them: `n" $Resource_Pools_Without_VMs
}

#############################################################################################

function Hand_Over_Pod
{
<#
.SYNOPSIS
Change permissions on Pod.

.DESCRIPTION
Takes Pod provided in parameter and removes the permissions for that original user then changes it to the secondary user, also renames resource pool and folder.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Resource_Pool
Name of Resource_Pool object to hand over.

.PARAMETER Username
Domain Username to change permissions to.

.EXAMPLE
PS > Hand_Over_Pod "ABCD001 - jsmith" "mjohnson"
#>
    
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Username)

#Remember the username without the Costco prefix
$Chopped_Username = $Username
#Convert username to have Costco prefix
$Username = "$Domain$Username"
#Get the user that currently has the pod
$Original_User = "$Domain" + (Get_Username_From_Resource_Pool $Resource_Pool)
#Get the permissions objects assigned to the resource pool
$Original_Resource_Pool_Permission = Get-VIPermission -Entity (Get-ResourcePool $Resource_Pool) -Principal $Original_User
$Original_Folder_Permission = Get-VIPermission -Entity (Get-Folder $Resource_Pool) -Principal $Original_User
#Remove permissions on original user
Write-Host "Removing permissions for $Original_User on folder/resource pool $Resource_Pool"
$null = Remove-VIPermission -Permission $Original_Resource_Pool_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_Folder_Permission -Confirm:$false
#Set the new permissions for the new user
Set_Resource_Pool_Permissions $Resource_Pool $Username
Set_Folder_Permissions $Resource_Pool $Username
$VMs_In_Resource_Pool = @()
$VMs_In_Resource_Pool = Get-ResourcePool -Name $Resource_Pool | Get-VM | foreach{$_.name}
#Get the VMs in the resource pool and assign those permissions appropriately
if ($VMs_In_Resource_Pool -ne $null){
foreach($VM in $VMs_In_Resource_Pool){
$Original_VM_Permission = Get-VIPermission -Entity (Get-VM $VM) -Principal $Original_User
Write-Host "Removing permission for VM $VM inside $Resource_Pool"
#Remove original user, set new user
$null = Remove-VIPermission -Permission $Original_VM_Permission -Confirm:$false
Set_VM_Permissions $Resource_Pool $Username
}
}
#Name the resource pool
$New_Resource_Pool = (Get_Resource_Pool_Prefix $Resource_Pool) + " - $Chopped_Username"
Set-ResourcePool -ResourcePool $Resource_Pool -Name $New_Resource_Pool
Set-Folder -Folder $Resource_Pool -name $New_Resource_Pool

#Get the currently permissions on the port group
$Resource_Pool_Prefix = Get_Resource_Pool_Prefix $Resource_Pool
$Management_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$Management_PortGroup_ID-*"
$A_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$A_PortGroup_ID-*"
$B_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$B_PortGroup_ID-*"
$C_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$C_PortGroup_ID-*"
$D_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$D_PortGroup_ID-*"

#Set the new permissions on the port group
Write-Host "Removing permissions for the port groups for $Original_User"
$Original_Management_Permission = Get-VIPermission -Entity $Management_Interface -Principal $Original_User
$Original_A_Permission = Get-VIPermission -Entity $A_Interface -Principal $Original_User
$Original_B_Permission = Get-VIPermission -Entity $B_Interface -Principal $Original_User
$Original_C_Permission = Get-VIPermission -Entity $C_Interface -Principal $Original_User
$Original_D_Permission = Get-VIPermission -Entity $D_Interface -Principal $Original_User
$null = Remove-VIPermission -Permission $Original_Management_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_A_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_B_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_C_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_D_Permission -Confirm:$false
#Set the router permissions
Set_Router_Permissions $New_Resource_Pool $Username
}

#############################################################################################

function Notify_User
{
<#
.SYNOPSIS
Sends default email to user after creating POD.

.DESCRIPTION
Uses Costco SMTP Server variable to send email to user.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.EXAMPLE
PS > Notify_User jsmith "ABCD001 - jsmith"
#>
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Username,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool)


$Username= $Username.trimstart($Domain)

$VPP_VLANs = Get_POD_VPP_VLANs $Resource_Pool
$MGMT_VLAN = Get_POD_MGMT_VLAN $Resource_Pool

$Pod = Get_Resource_Pool_Prefix $Resource_Pool
$Pod_User = $pod.tolower()
$SMTP_To = "$Username@Costco.com"
$Message_Subject = "Your GCP POD $Pod is READY"
#Default Message
$Message_Body_Prefix = "Hi $Username,`n`nYour GCP POD has been created and within the next 60 minutes you should be able to access it via the below information.`n`nYou are POD number - $Pod`nDNS for your POD is - $Pod.$domain_com`nPFsense router for the POD is - https://$Pod-pod.$domain_com:9443`n`nLogin info for your PFsense router:`nUsername: $Pod_User`nPassword: $Pod_User`n`nYou now have access to the following virtual port groups that map to VLANs on the VPP: `n(NOTE: the suffix represents the VLAN i.e ABCD001-A-1501, 1501 is the VLAN)`n$VPP_VLANs`n`nYou should also use $MGMT_VLAN for devices routing out to the internet.`n`n"
$Message = $Message_Body_Prefix + $Message_Body_Default
Write-Color -Text "STATUS:"," Sending email to ","$SMTP_To"," now..." -Color Cyan,Gray,Yellow,Gray
Send-MailMessage -SmtpServer $SMTP_Server -From $SMTP_From -To $SMTP_To -Subject $Message_Subject -Body $Message
}

#############################################################################################

function Assign_User_To_Pod
{
<#
.SYNOPSIS
Assigns a particular user to a POD.

.DESCRIPTION
Takes Domain user and assigns them to a specific POD.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.EXAMPLE
PS > Assign_User_To_Pod mjohnson "ABCD001 - jsmith"
#>
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Username,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool)

if ($Username.Startswith("$Domain") -eq $false){
$Username = "$Domain$Username"
}
Set_Resource_Pool_Permissions $Resource_Pool $Username
Set_Folder_Permissions $Resource_Pool $Username
Set_Router_Permissions $Resource_Pool $Username
}

#############################################################################################

function Unassign_User_To_Pod
{
<#
.SYNOPSIS
Unassigns a particular user to a POD.

.DESCRIPTION
Takes Domain user and unassigns them to a specific POD.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Username
Domain Username to remove permissions from.

.PARAMETER Resource_Pool
Name of Resource_Pool object to remove permissions from.

.EXAMPLE
PS > Unassign_User_To_Pod jsmith "ABCD001 - jsmith"
#>
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Username,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool)

if ($Username.Startswith("$Domain") -eq $false){
$Username = "$Domain$Username"
}

$Original_Resource_Pool_Permission = Get-VIPermission -Entity (Get-ResourcePool $Resource_Pool) -Principal $Username
$Original_Folder_Permission = Get-VIPermission -Entity (Get-Folder $Resource_Pool) -Principal $Username
#Remove permissions on original user
Write-Host "Removing permissions for $Original_User on folder/resource pool $Resource_Pool"
$null = Remove-VIPermission -Permission $Original_Resource_Pool_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_Folder_Permission -Confirm:$false

$VMs_In_Resource_Pool = @()
$VMs_In_Resource_Pool = Get-ResourcePool -Name $Resource_Pool | Get-VM | foreach{$_.name}
#Get the VMs in the resource pool and assign those permissions appropriately
if ($VMs_In_Resource_Pool -ne $null){
foreach($VM in $VMs_In_Resource_Pool){
$Original_VM_Permission = Get-VIPermission -Entity (Get-VM $VM) -Principal $Original_User
Write-Host "Removing permission for VM $VM inside $Resource_Pool"
#Remove original user, set new user
$null = Remove-VIPermission -Permission $Original_VM_Permission -Confirm:$false
}
}

#Get the currently permissions on the port group
$Resource_Pool_Prefix = Get_Resource_Pool_Prefix $Resource_Pool
$Management_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$Management_PortGroup_ID-*"
$A_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$A_PortGroup_ID-*"
$B_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$B_PortGroup_ID-*"
$C_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$C_PortGroup_ID-*"
$D_Interface = Get-VDPortGroup -name "$Resource_Pool_Prefix-$D_PortGroup_ID-*"

#Set the new permissions on the port group
Write-Color -Text "STATUS: ", "Removing permissions for the port groups for", " $Original_User" -Color Cyan, Gray, Yellow
$Original_Management_Permission = Get-VIPermission -Entity $Management_Interface -Principal $Username
$Original_A_Permission = Get-VIPermission -Entity $A_Interface -Principal $Username
$Original_B_Permission = Get-VIPermission -Entity $B_Interface -Principal $Username
$Original_C_Permission = Get-VIPermission -Entity $C_Interface -Principal $Username
$Original_D_Permission = Get-VIPermission -Entity $D_Interface -Principal $Username
$null = Remove-VIPermission -Permission $Original_Management_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_A_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_B_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_C_Permission -Confirm:$false
$null = Remove-VIPermission -Permission $Original_D_Permission -Confirm:$false
}

#############################################################################################

function Create_Group_POD
{
<#
.SYNOPSIS
Creates a POD for a group in AD.

.DESCRIPTION
Takes Domain group and assigns them to a Resource Pool/Folder and Router.  Also allows for more than the default 4 networks.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Group
Domain Group to assign to Resource Pool.

.PARAMETER Team
Team to assign to Resource Pool for designation.

.PARAMETER Private_Networks
How many private networks.

.EXAMPLE
PS > Create_Group_POD "sf_qa_user_group" "ClamAV" 20
#>
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Group,
    [Parameter(Position = 1, Mandatory = $True, Parametersetname="Exfil")] [String]$Team,
    [Parameter(Position = 2, Mandatory = $True, Parametersetname="Exfil")] [String]$Private_Networks)

$MGMT_Vlan = Find_Next_MGMT_VLAN
$Next_Vlan = Find_Next_Group_VLAN

$MGMT_Vlan
$Next_Vlan

$Resource_Pool = "$User_Resource_Pool_Prefix - $Team"
$Folder = "$User_Resource_Pool_Prefix - $Team"
Write-Color -Text "STATUS: ", "Creating Resource Pool"," $Resource_Pool"," now..." -Color Cyan,Gray,Yellow,Gray
$null = New-ResourcePool -Location $Groups_Resource_Pool -Name $Resource_Pool
Write-Color -Text "STATUS: ","Creating Folder"," $Folder"," now..." -Color Cyan,Gray,Yellow,Gray
$null = New-Folder -Location $Groups_Folder -Name $Folder
$Group = "$Domain$Group"
Set_Resource_Pool_Permissions $Resource_Pool $Group
Set_Folder_Permissions $Folder $Group

$Datastore = Get_Datastore
$Datastore = Get-Datastore -Location $GCP_Datacenter -name $Datastore

#Create Port Groups
$PG_Name_Prefix = ($Resource_Pool -replace " ", "")

Write-Color -Text "STATUS: ","Creating Management VLAN for POD..." -Color Cyan,Gray
Write-Host "Using VLAN: $MGMT_Vlan"
$MGMT_PG = "$PG_Name_Prefix-MGMT-$MGMT_Vlan"
$null = New-VDPortGroup -vdSwitch $dvSwitchName -name "$MGMT_PG" -NumPorts 128 -VLanId $MGMT_Vlan
$Interface = Get-VDPortGroup -name "$MGMT_PG"
$null = New-VIPermission -Entity $Interface -Principal $Group -Role $VM_Network_Role

$i = 1
Write-Color -Text "STATUS: ", "Creating ","$Private_Networks"," Port Groups for POD..." -Color Cyan,Gray,Yellow,Gray

foreach($_ in $i..$Private_Networks){
Write-Color -Text "STATUS: ", "Creating ","$i"," of ","$Private_Networks","..." -Color Cyan,Gray,Yellow,Gray,Yellow,Gray
Write-Host "Using VLAN: $Next_Vlan"
$null = New-VDPortGroup -vdSwitch $dvSwitchName -name "$PG_Name_Prefix-$Next_Vlan" -NumPorts 16 -VLanId $Next_Vlan
$null = Get-VDPortGroup "$PG_Name_Prefix-$Next_Vlan" | Get-VDSecurityPolicy | Set-VDSecurityPolicy -ForgedTransmits $True -AllowPromiscuous $True
$Interface = Get-VDPortGroup -name "$PG_Name_Prefix-$Next_Vlan"
$null = New-VIPermission -Entity $Interface -Principal $Group -Role $VM_Network_Role

$Next_Vlan = $Next_Vlan + 1
$i++
}

$VM_Name = ($Resource_Pool -replace " ", "") + "-" + "$Router_Name"
$null = New-VM -Location (Get-Folder $Router_Folder) -Template $Router_Template -Datastore $Datastore -Name $VM_Name -ResourcePool $Routers_Resource_Pool -ErrorAction "SilentlyContinue"
Start-Sleep -s 10
Write-Color -Text "STATUS: ","Placing eth0 for vRouter to ","$Jump_VLAN"," now..." -Color Cyan,Gray,Yellow,Gray
$null = Get-VM $VM_Name | Get-NetworkAdapter -name "Network adapter 1" | Set-NetworkAdapter -NetworkName $Jump_VLAN -Confirm:$false
$Internal_Interface = Get-VDPortGroup -name "$MGMT_PG"
Write-Color -Text "STATUS: ","Placing eth1 for vRouter to ","$Internal_Interface"," now..." -Color Cyan,Gray,Yellow,Gray
$null = Get-VM $VM_Name | Get-NetworkAdapter -name "Network adapter 2" | Set-NetworkAdapter -NetworkName $Internal_Interface -Confirm:$false
Write-Color -Text "STATUS: ","Powering on ","$VM_Name", " now..." -Color Cyan,Gray,Yellow,Gray
$null = Start-VM $VM_Name -Confirm:$false
}

#############################################################################################

function Create_Multiple_PODs
{
<#
.SYNOPSIS
Creates a pod for each user specified as a parameter.

.DESCRIPTION
Creates a pod for each user specified as a parameter.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Users
Comma seperated list of users to create pods for.

.EXAMPLE
PS > Create_Multiple_PODs "kvidmar,smcmulle,mminkin,jsmith"
#>
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Users)

$AllUsers = @()
$Users = $Users -replace " ", ""
$AllUsers = $Users -split ","

foreach($User in $AllUsers){
    Create_Resource_Pool_And_Folder $User
}
}

#############################################################################################

function Find_Next_Group_VLAN
{
<#
.SYNOPSIS
Finds next available group VLAN available for use.

.DESCRIPTION
Finds next available group VLAN available for use.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.EXAMPLE
PS > Find_Next_Group_VLAN
#>

$Port_Group = $null
$Next_Port_Group = $null

$Port_Group = Get-VDPortGroup -vdswitch $dvSwitchName | Where-Object{$_.name -like "$User_Resource_Pool_Prefix-*" -and $_.name -notlike "*$Management_PortGroup_ID*"} | foreach{($_.name -replace "[a-zA-Z\-]","")}
$Port_Group = $Port_Group | sort | select -last 1
if ($Port_Group -eq $null -and $Port_Group -eq ""){[int]$Next_Port_Group = [int]$Group_VLAN_Start}
else{[int]$Next_Port_Group = (([int]$Port_Group) + 1)}
$Next_Port_Group = [int]$Next_Port_Group
Return $Next_Port_Group
}

#############################################################################################

function Find_Next_MGMT_VLAN
{
<#
.SYNOPSIS
Finds next available MGMT VLAN available for use.

.DESCRIPTION
Finds next available MGMT VLAN available for use.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.EXAMPLE
PS > Find_Next_MGMT_VLAN ClamAV
#>

$Port_Group = $null
$Next_Port_Group = $null

$Characters_To_Trim = ($User_Resource_Pool_Prefix.Length + $Digits_In_Numeric_Identifier)

$Port_Group = Get-VDPortGroup -vdSwitch $dvSwitchName | Where-Object{$_.name -like "$User_Resource_Pool_Prefix*-$Management_PortGroup_ID*"} | foreach{($_.name -creplace '(?s)^.*\-', '')}
$Port_Group = $Port_Group | sort | select -last 1
    if ($Port_Group -eq $null){$Next_Port_Group = [int]$MGMT_Start}
    else{$Next_Port_Group = (([int]$Port_Group) + 1)}
$Next_Port_Group = [int]$Next_Port_Group
Return [int]$Next_Port_Group
}

#############################################################################################

function Find_Next_Individual_VLAN
{
<#
.SYNOPSIS
Finds next available VLAN available for use within individual PODs.

.DESCRIPTION
Finds next available VLAN available for use within individual PODs.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.EXAMPLE
PS > Find_Next_Individual_VLAN
#>

$Characters_To_Trim = ($User_Resource_Pool_Prefix.Length + $Digits_In_Numeric_Identifier)

$Port_Group = Get-VDPortGroup -vdSwitch $dvSwitchName | Where-Object{$_.name -like "$User_Resource_Pool_Prefix*-$A_PortGroup_ID-*" -or $_.name -like "$User_Resource_Pool_Prefix*-$B_PortGroup_ID-*" -or $_.name -like "$User_Resource_Pool_Prefix*-$C_PortGroup_ID-*" -or $_.name -like "$User_Resource_Pool_Prefix*-$D_PortGroup_ID-*" } | foreach{(($_.name.substring($Characters_To_Trim)) -replace "[a-zA-Z\-]","")}
$Port_Group = $Port_Group | sort | select -last 1
    if ($Port_Group -eq $null){$Next_Port_Group = $Individual_Start}
    else{$Next_Port_Group = ([int]$Port_Group + 1)}

Return $Next_Port_Group
}

#############################################################################################

function Create_Individual_Port_Groups
{
<#
.SYNOPSIS
Checks to see if port groups exist for individual PODs.

.DESCRIPTION
Checks to see if port groups exist for individual PODs.  If not, creates them.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Resource_Pool_Prefix
Resource pool to check/create for.

.EXAMPLE
PS > Create_Individual_Port_Groups "CLMM146 - kvidmar"
#>
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool_Prefix)


$Check = Get-VDPortGroup -vdSwitch $dvSwitchName | Where-Object {$_.name -like "$Resource_Pool_Prefix*"}
if ($Check -eq $null){
Write-Color -Text "STATUS: ","Port groups do not exist for POD, creating them now..." -Color Cyan, Gray
$Next_Individual_VLAN = Find_Next_Individual_VLAN
$Next_MGMT_VLAN = Find_Next_MGMT_VLAN

$null = New-VDPortGroup -vdSwitch $dvSwitchName -name "$Resource_Pool_Prefix-$Management_PortGroup_ID-$Next_MGMT_VLAN" -NumPorts 128 -VLanId $Next_MGMT_VLAN
##
$null = New-VDPortGroup -vdSwitch $dvSwitchName -name "$Resource_Pool_Prefix-$A_PortGroup_ID-$Next_Individual_VLAN" -NumPorts 16 -VLanId $Next_Individual_VLAN
$null = Get-VDPortGroup "$Resource_Pool_Prefix-$A_PortGroup_ID-$Next_Individual_VLAN" | Get-VDSecurityPolicy | Set-VDSecurityPolicy -ForgedTransmits $True -AllowPromiscuous $True
$Next_Individual_VLAN++
###
$null = New-VDPortGroup -vdSwitch $dvSwitchName -name "$Resource_Pool_Prefix-$B_PortGroup_ID-$Next_Individual_VLAN" -NumPorts 16 -VLanId $Next_Individual_VLAN
$null = Get-VDPortGroup "$Resource_Pool_Prefix-$B_PortGroup_ID-$Next_Individual_VLAN" | Get-VDSecurityPolicy | Set-VDSecurityPolicy -ForgedTransmits $True -AllowPromiscuous $True
$Next_Individual_VLAN++
###
$null = New-VDPortGroup -vdSwitch $dvSwitchName -name "$Resource_Pool_Prefix-$C_PortGroup_ID-$Next_Individual_VLAN" -NumPorts 16 -VLanId $Next_Individual_VLAN
$null = Get-VDPortGroup "$Resource_Pool_Prefix-$C_PortGroup_ID-$Next_Individual_VLAN" | Get-VDSecurityPolicy | Set-VDSecurityPolicy -ForgedTransmits $True -AllowPromiscuous $True
$Next_Individual_VLAN++
###
$null = New-VDPortGroup -vdSwitch $dvSwitchName -name "$Resource_Pool_Prefix-$D_PortGroup_ID-$Next_Individual_VLAN" -NumPorts 16 -VLanId $Next_Individual_VLAN
$null = Get-VDPortGroup "$Resource_Pool_Prefix-$D_PortGroup_ID-$Next_Individual_VLAN" | Get-VDSecurityPolicy | Set-VDSecurityPolicy -ForgedTransmits $True -AllowPromiscuous $True

}
else{
Write-Color -Text "STATUS: ","Port groups already exist for POD, carrying on." -Color Cyan, Gray
}
}


#############################################################################################

function Write-Color([String[]]$Text, [ConsoleColor[]]$Color) {
<#
.SYNOPSIS
Simple function to write status in different colors.

.EXAMPLE
PS > Write-Color -Text Red,White,Blue -Color Red,White,Blue
#>

    for ($i = 0; $i -lt $Text.Length; $i++) {
        Write-Host $Text[$i] -Foreground $Color[$i] -NoNewLine
    }
    Write-Host
}

#############################################################################################

function Get_POD_VPP_VLANs
{
<#
.SYNOPSIS
Returns a list of VLANs assigned to a pod.

.DESCRIPTION
Will provide a list of VLANs associated with the dvSwitch tied to PODs.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Resource_Pool
Resource pool to check for.

.EXAMPLE
PS > Get_Pod_VLANs "ABCD001 - jsmith"
#>
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool)

$Resource_Pool_Prefix = Get_Resource_Pool_Prefix $Resource_Pool
$Port_Groups = @()
$VPP_Port_Groups = @()
$Port_Groups = Get-VDPortGroup -VDSwitch $dvSwitchName | Where-Object{$_.name -like "$Resource_Pool_Prefix*"} | foreach{$_.name}

$VPP_Port_Groups = $Port_Groups | Where-object{$_ -notlike "*$Management_PortGroup_ID*"}
$VPP_Port_Groups = $VPP_Port_Groups | sort
$VPP_Port_Groups = $VPP_Port_Groups -join "`n"
Return $VPP_Port_Groups
}

#############################################################################################

function Get_POD_MGMT_VLAN
{
<#
.SYNOPSIS
Returns a list of VLANs assigned to a pod.

.DESCRIPTION
Will provide a list of VLANs associated with the dvSwitch tied to PODs.

.PARAMETER Exfil
Use this parameter to use exfiltration methods.

.PARAMETER Resource_Pool
Resource pool to check for.

.EXAMPLE
PS > Get_Pod_VLANs "ABCD001 - jsmith"
#>
    [CmdletBinding(DefaultParameterSetName="noexfil")]
    Param ([Parameter(Parametersetname="Exfil")] [Switch]$Exfil,
    [Parameter(Position = 0, Mandatory = $True, Parametersetname="Exfil")] [String]$Resource_Pool)

$Resource_Pool_Prefix = Get_Resource_Pool_Prefix $Resource_Pool
$Port_Groups = @()
$VPP_Port_Groups = @()
$Port_Groups = Get-VDPortGroup -VDSwitch $dvSwitchName | Where-Object{$_.name -like "$Resource_Pool_Prefix*"} | foreach{$_.name}

$MGMT_Port_Group = $Port_Groups | Where-object{$_ -like "*$Management_PortGroup_ID*"}
Return $MGMT_Port_Group
}
