<#
    .DESCRIPTION
        Sample script to enable WASM workloads with AKS Edge
#>

param(
    [string] $shimVersion = "v0.3.3",
    [ValidateSet("spin", "slight", "both")]
    [string] $shimOption = "both"
)

Write-Host "1. Checking AKS dependencies" -ForegroundColor Green
$IsK3s = (kubectl get nodes) | Where-Object { $_ -match "k3s"}
$IsK8s =(kubectl get nodes) | Where-Object { $_ -match "v1.24.3"}
if ($IsK3s) {
    Write-Host "    AKS K3s version found" -ForegroundColor Cyan
}
elseif ($IsK8s) {
    Write-Host "    AKS K8s version found" -ForegroundColor Cyan
}
 else {
    Write-Host "No AKS K3s/K8s version found - Please install and try again" -ForegroundColor Red
    exit -1
}

Write-Host "Downloading shim verison $shimVersion" -ForegroundColor green
Invoke-AksEdgeNodeCommand "wget -O /home/aksedge-user/containerd-wasm-shim.tar.gz https://github.com/deislabs/containerd-wasm-shims/releases/download/$shimVersion/containerd-wasm-shims-v1-linux-x86_64.tar.gz"

Write-Host "Unpacking and moving shim to appropiate folder" -ForegroundColor green
Invoke-AksEdgeNodeCommand "tar -xvf /home/aksedge-user/containerd-wasm-shim.tar.gz && sudo mkdir /var/lib/bin" | Out-Null

if($shimOption -eq "both")
{
    Invoke-AksEdgeNodeCommand "sudo mv /home/aksedge-user/containerd-shim-spin-v1 /var/lib/bin/"  | Out-Null
    Invoke-AksEdgeNodeCommand "sudo mv /home/aksedge-user/containerd-shim-slight-v1 /var/lib/bin/ && sudo rm /home/aksedge-user/containerd-*"  | Out-Null
}
else
{
    Invoke-AksEdgeNodeCommand "sudo mv /home/aksedge-user/containerd-shim-$shimOption-v1 /var/lib/bin/ && sudo rm /home/aksedge-user/containerd-*"  | Out-Null
}


Write-Host "Copying required files" -ForegroundColor green
if($IsK8s)
{
    Invoke-AksEdgeNodeCommand -NodeType Linux "sudo cp /etc/containerd/config.toml /home/aksedge-user/config.toml"
}
else
{
    Invoke-AksEdgeNodeCommand -NodeType Linux "sudo cp /var/lib/rancher/k3s/agent/etc/containerd/config.toml /home/aksedge-user/config.toml"
}

Invoke-AksEdgeNodeCommand -NodeType Linux "sudo chown -R aksedge-user /home/aksedge-user/config.toml"
Copy-AksEdgeNodeFile -NodeType Linux -FromFile "/home/aksedge-user/config.toml" -ToFile ".\config.toml"

Write-Host "Configuring containerd config files to support runwasi runtime" -ForegroundColor green


if($shimOption -eq "both")
{
    $command = "`n[plugins.cri.containerd.runtimes.spin]`n  runtime_type = ""io.containerd.spin.v1""`n[plugins.cri.containerd.runtimes.slight]`n  runtime_type = ""io.containerd.slight.v1"""
    if($IsK8s)
    {
        $command =  "`n[plugins.""io.containerd.grpc.v1.cri"".containerd.runtimes.slight]`n  runtime_type = ""io.containerd.slight.v1""`n[plugins.""io.containerd.grpc.v1.cri"".containerd.runtimes.spin]`n  runtime_type = ""io.containerd.spin.v1"""
    }
    Add-Content -Path ".\config.toml" $command     
}
else
{
    $command = "`n[plugins.cri.containerd.runtimes.$shimOption]`n  runtime_type = ""io.containerd.$shimOption.v1"""
    if($IsK8s)
    {
        $command =  "`n[plugins.""io.containerd.grpc.v1.cri"".containerd.runtimes.$shimOption]`n  runtime_type = ""io.containerd.$shimOption.v1"""
    }
    Add-Content -Path ".\config.toml" $command  
}

Copy-AksEdgeNodeFile -NodeType Linux -FromFile ".\config.toml" -ToFile "/home/aksedge-user/config.toml" -PushFile
if($IsK8s)
{
    Invoke-AksEdgeNodeCommand -NodeType Linux "sudo cp /home/aksedge-user/config.toml /etc/containerd/config.toml"   
}
else
{
    Invoke-AksEdgeNodeCommand -NodeType Linux "sudo cp /home/aksedge-user/config.toml /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl"
}

Write-Host "Cleaning unnecessary files" -ForegroundColor green

Invoke-AksEdgeNodeCommand -NodeType Linux "sudo rm /home/aksedge-user/config.toml"
Remove-Item -Path ".\config.toml"

Write-Host "Adding new runwasi directory to  PATH variable" -ForegroundColor green
$currentPath = Invoke-AksEdgeNodeCommand 'echo $PATH'
$newPath = "PATH=" + $currentPath + ":/var/lib/bin"
Write-Host "Current PATH=$currentPath - New $newPath" -ForegroundColor green

$kubeService = "k3s"
if($IsK8s)
{
    $kubeService = "containerd"
}
Write-Host "Configuring $kubeService service with new configuration" -ForegroundColor green

Invoke-AksEdgeNodeCommand -NodeType Linux "sudo cp /etc/systemd/system/$kubeService.service.d/override.conf /home/aksedge-user/override.conf"
Invoke-AksEdgeNodeCommand -NodeType Linux "sudo chown -R aksedge-user /home/aksedge-user/override.conf"
Copy-AksEdgeNodeFile -NodeType Linux -FromFile "/home/aksedge-user/override.conf" -ToFile ".\override.conf"

$command = "Environment=""$newPath"""
Add-Content -Path ".\override.conf" $command  
Copy-AksEdgeNodeFile -NodeType Linux -FromFile ".\override.conf" -ToFile "/home/aksedge-user/override.conf" -PushFile

Invoke-AksEdgeNodeCommand -NodeType Linux "sudo rm /home/aksedge-user/override.conf"
Remove-Item -Path ".\override.conf"

Invoke-AksEdgeNodeCommand -NodeType Linux "sudo cp /home/aksedge-user/override.conf /etc/systemd/system/$kubeService.service.d/override.conf"
Invoke-AksEdgeNodeCommand "sudo systemctl daemon-reload"
Invoke-AksEdgeNodeCommand "sudo systemctl restart $kubeService"

Write-Host "Configuration finished - You can now deploy WASM workloads using kubectl interface" -ForegroundColor green