# Utilize Akri devices on WASM workloads using AKS Edge Essentials

## Introduction

This sample demonstrates how to deploy Akri to conenct an ONVIF camera to your AKS Edge Essentials cluster and run an ONNX payload on WASM using [containerd-wasm-shim](https://github.com/deislabs/containerd-wasm-shims) inside the cluster.

Akri only works on Linux nodes and **containerd-wasm-shim** only supports Linux nodes; Winodws nodes support is under development.

 _:warning: **WARNING**_: _This sample is experimental only and is not intended for production deployments. **containerd-wasm-shim** is currently in **alpha** version._

## Prerequisites

- You will need an ONVIF camera for this demo.
- Check [AKS Edge Essentials requirements and support matrix](https://learn.microsoft.com/azure/aks/hybrid/aks-edge-system-requirements).



## Instructions

1. Setup AKS Edge Essentials - Follow docs to [set up machine](https://aka.ms/aks-edge/quickstart).
2. Deploy a [scalable cluster](https://learn.microsoft.com/azure/aks/hybrid/aks-edge-howto-multi-node-deployment) using an external switch and set service IP range to `10`.
3. Open an elevated PowerShell session.
4. Move to an appropriate working directory
5. Download [Set-AksEdgeWasmRuntime.ps1](./Set-AksEdgeWasmRuntime.ps1):
    ```powershell
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Azure/AKS-Edge/preview/samples/wasm/Set-AksEdgeWasmRuntime.ps1" -OutFile ".\Set-AksEdgeWasmRuntime.ps1"
    Unblock-File -Path ".\Set-AksEdgeWasmRuntime.ps1"
    ```
6. Run the `Set-AksEdgeWasmRuntime` cmdlet to enable the *containerd-wasm-shim*. We will be using **v0.4.0** for this demo.

    ```powershell
    .\Set-AksEdgeWasmRuntime.ps1 -enable -shimVersion v0.4.0
    ```

   | Parameter | Options | Description | 
   | --------- | ------- | ----------- |
   | enable | None | If this flag is present, the command enables the feature.|
   | shimOption | spin, slight, both | containerd-wasm-shim version. For more information, see https://github.com/deislabs/containerd-wasm-shims |
   | shimVersion | None | containerd-wasm-shim version. For more information, see https://github.com/deislabs/containerd-wasm-shims |
    

7. Apply the *runtime.yaml* to create the *wasmtime-slight* and *wasmtime-spin* rumtime classes.

    ```powershell
    kubectl apply -f https://github.com/deislabs/containerd-wasm-shims/releases/download/v0.4.0/runtime.yaml
    ```
    
    If everything was correctly created, you should see the two runtime classes.

    ```bash
    NAME              HANDLER   AGE
    wasmtime-slight   slight    5s
    wasmtime-spin     spin      5s
    ```
8. Add the Akri helm charts if you've haven't already:

    ```powershell
    helm repo add akri-helm-charts https://project-akri.github.io/akri/
    ```
    
    If you have already added Akri helm chart previously, update your repo for the latest build:
    
    ```powershell
    helm repo update
    ```

9. Install Akri using Helm. When installing Akri, specify that you want to deploy the ONVIF discovery handlers by setting the helm value `onvif.discovery.enabled=true`. Also, specify that you want to deploy the ONVIF video broker:  
    
   ```powershell
   helm install akri akri-helm-charts/akri `
    --set kubernetesDistro=<insert k3s or k8s depending on what you are using> `
    --set onvif.discovery.enabled=true `
    --set onvif.configuration.enabled=true `
    --set onvif.configuration.capacity=2 `
    --set onvif.configuration.brokerPod.image.repository='ghcr.io/project-akri/akri/onvif-video-broker' `
    --set onvif.configuration.brokerPod.image.tag='latest'
   ```
   
   Learn more about the [ONVIF configuration settings here](https://docs.akri.sh/discovery-handlers/onvif).

10. Run the following command to open port for WS-Discovery within the Linux node and save the IP tables:

    ```powershell
    Invoke-AksEdgeNodeCommand -command "sudo iptables -A INPUT -p udp --sport 3702 -j ACCEPT"
    Invoke-AksEdgeNodeCommand -command "sudo iptables-save | sudo tee /etc/systemd/scripts/ip4save > /dev/null"
    ```
    
11. Verify that Akri can now discover your camera. You should see an Akri instance for your ONVIF camera:

    ```powershell
    kubectl get akrii
    ``` 

12. Now install the [WASM ONNX workload](./wasm-onnx.yaml) which will run inferencing on the frames coming from your camera:

    ```powershell
    kubectl apply -f wasm-onnx.yaml
    ```

13. Download the [akri-video-streaming-app.yaml](./akri-video-streaming-app.yaml) and open file. Go to line 30 and edit the value with your own WASM service external IP and port (`kubectl get svc` to find this).

14. Save and close the YAML. Then deploy the app:
    ```powershell
    kubectl apply -f akri-video-streaming-app.yaml
    ```

15. Run `Get-AKSEdgeNodeAddr` and `kubectl get svc`. In your browser, go to `<Node Address>:<Port of streaming app service>`. You should be able to see the stream from your camera and the boundary box for inferencing.

## Clean up deployment

Once you're finished with WASM workloads, clean up your workspace by running the following commands.

1. Open an elevated PowerShell session  
1. Delete all resources
    ```powershell
    kubectl delete -f akri-video-streaming-app.yaml
    kubectl delete -f wasm-onnx.yaml
    helm delete akri
    .\Set-AksEdgeWasmRuntime.ps1
    ```

## Feedback

If you have problems with this sample, please post an issue in this repository.