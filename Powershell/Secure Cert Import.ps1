# Get the certificate from the remote server
$ServerName = "rdprofiles-2019.marquiscompanies.com"
$Port = 5986

function Verify_Certificate {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    
    # Check if certificate is expired
    if ($Certificate.NotAfter -lt (Get-Date) -or $Certificate.NotBefore -gt (Get-Date)) {
        Write-Error "Certificate is not valid at current date"
        return $false
    }
    
    # Verify certificate is meant for server authentication
    $serverAuth = "1.3.6.1.5.5.7.3.1"
    $hasServerAuth = $Certificate.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq $serverAuth }
    if (-not $hasServerAuth) {
        Write-Error "Certificate is not meant for server authentication"
        return $false
    }
    
    # Verify certificate subject matches server name
    if (-not $Certificate.Subject.Contains($ServerName)) {
        Write-Error "Certificate subject does not match server name"
        return $false
    }
    
    # Build and validate certificate chain
    $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $chain.ChainPolicy.RevocationFlag = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::EntireChain
    $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
    $chain.ChainPolicy.UrlRetrievalTimeout = New-TimeSpan -Seconds 30
    
    $isValid = $chain.Build($Certificate)
    
    if (-not $isValid) {
        foreach ($element in $chain.ChainElements) {
            if ($element.Status -ne 'Valid') {
                Write-Error "Certificate chain validation failed: $($element.Status)"
            }
        }
        return $false
    }
    
    return $true
}

Write-Host "Retrieving certificate from $ServerName`:$Port..."
$Cert = $null
try {
    # Create a TCP client to connect to the server
    $TcpClient = New-Object System.Net.Sockets.TcpClient
    $TcpClient.Connect($ServerName, $Port)
    
    # Create an SSL stream with proper validation
    $SslStream = New-Object System.Net.Security.SslStream(
        $TcpClient.GetStream(),
        $false,
        [System.Net.Security.RemoteCertificateValidationCallback]::new({
            param($sender, $certificate, $chain, $errors)
            
            if ($errors -ne [System.Net.Security.SslPolicyErrors]::None) {
                Write-Error "SSL Policy Errors: $errors"
                return $false
            }
            return $true
        })
    )
    
    # Attempt SSL authentication with proper validation
    $SslStream.AuthenticateAsClient(
        $ServerName,
        $null,  # No client certificates
        [System.Security.Authentication.SslProtocols]::Tls12,  # Force TLS 1.2
        $true   # Check certificate revocation
    )
    
    $Cert = $SslStream.RemoteCertificate
    if ($Cert) {
        # Convert to X509Certificate2 if needed
        if ($Cert -isnot [System.Security.Cryptography.X509Certificates.X509Certificate2]) {
            $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Cert)
        }
        
        # Verify certificate
        if (-not (Verify-Certificate -Certificate $Cert)) {
            throw "Certificate verification failed"
        }
        
        # Show certificate details and prompt for confirmation
        Write-Host "`nCertificate Details:"
        Write-Host "Subject: $($Cert.Subject)"
        Write-Host "Issuer: $($Cert.Issuer)"
        Write-Host "Valid From: $($Cert.NotBefore)"
        Write-Host "Valid To: $($Cert.NotAfter)"
        Write-Host "Thumbprint: $($Cert.Thumbprint)"
        
        $confirmation = Read-Host "`nDo you want to trust this certificate? (y/n)"
        if ($confirmation -ne 'y') {
            throw "User cancelled certificate import"
        }
        
        # Save certificate with restricted permissions
        $CertPath = ".\server_cert.cer"
        [System.IO.File]::WriteAllBytes($CertPath, $Cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        $acl = Get-Acl $CertPath
        $acl.SetAccessRuleProtection($true, $false)
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","Allow")
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","Allow")
        $acl.AddAccessRule($adminRule)
        $acl.AddAccessRule($systemRule)
        Set-Acl $CertPath $acl
        
        # Import to Trusted Root store with proper security context
        $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
            [System.Security.Cryptography.X509Certificates.StoreName]::Root,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
        )
        
        try {
            $Store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $Store.Add($Cert)
            Write-Host "Certificate successfully imported to Trusted Root store"
        }
        finally {
            $Store.Close()
        }
    }
}
catch {
    Write-Error "Error retrieving or importing certificate: $_"
}
finally {
    if ($SslStream) { $SslStream.Dispose() }
    if ($TcpClient) { $TcpClient.Dispose() }
}