# codeing免费没有了，手工同步原项目的代码到github,支持多个git ，大部分代码都来源于AI
# 第一步 申请gihub token
# 第二步 生成ssh 密钥 最好是空密码，临时用，用完删除，不然每个仓库都要手动输入密码,可能有其他免输方法
# 第三步 准备好相关参数 干活
$gitRepos = @(
   
"https://e.coding.net/xxxx/xxx/xxxx.git"
)
$githubUsername = "xxxxx"
$githubToken = "xxxxxx"
$githubApiUrl = "https://api.github.com/user/repos"
$tempDir = "E:\project\project_back"

# Create temporary directory for cloning
if (-Not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# Start SSH agent and add key (replace with your private key path)
Start-Service -Name ssh-agent -ErrorAction SilentlyContinue
ssh-add "$env:USERPROFILE\.ssh\id_rsa"

# Function to create a GitHub repository
function Create-GitHubRepo {
    param (
        [string]$repoName
    )
    $body = @{
        name = $repoName
        private = $true
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri $githubApiUrl -Method Post -Headers @{
        Authorization = "token $githubToken"
    } -Body $body -ContentType "application/json"

    if ($response -and $response.ssh_url) {
        Write-Host "GitHub repository '$repoName' created successfully."
        return $response.ssh_url
    } else {
        throw "Failed to create GitHub repository '$repoName'."
    }
}

# Process each repository
foreach ($repoUrl in $gitRepos) {
    try {
        # Extract repository name
        $urlParts = $repoUrl -split "/" | Where-Object { $_ -ne "" }
        $part1 = $urlParts[-2] 
        $part2 = $urlParts[-1]  
        $repoName = $part1 + "_" + ($part2 -replace ".git", "")

        # Clone the repository with source files
        $localRepoPath = Join-Path $tempDir $repoName
        Write-Host "Cloning repository '$repoName' to '$localRepoPath'..."
        git clone $repoUrl $localRepoPath
        Set-Location $localRepoPath

        # Fetch all branches and create local tracking branches
        git fetch --all
        
        # Create local branches for all remote branches
        foreach ($branch in (git branch -r | Where-Object { $_ -notmatch "HEAD" })) {
            $branchName = $branch.Trim() -replace "origin/", ""
            git checkout -b $branchName "origin/$branchName"
        }

        # Switch back to main/master branch
        if (git show-ref --verify --quiet refs/heads/main) {
            git checkout main
        } elseif (git show-ref --verify --quiet refs/heads/master) {
            git checkout master
        }

        # Create a new GitHub repository
        Write-Host "Creating GitHub repository '$repoName'..."
        $newRepoUrl = Create-GitHubRepo -repoName $repoName

        # Add GitHub remote and push all branches
        Write-Host "Pushing to GitHub repository..."
        git remote add github $newRepoUrl
        git push --all github
        git push --tags github

        Write-Host "Successfully migrated '$repoName' to GitHub with source files."
        Write-Host "Local source files available at: $localRepoPath"
        
        # List all files in the repository to verify
        Write-Host "Repository contents:"
        Get-ChildItem -Recurse -File | ForEach-Object { Write-Host "  - $($_.Name)" }
        
    } catch {
        Write-Host "Error processing repository '$repoUrl': $_" -ForegroundColor Red
    } finally {
        # Return to original directory
        Set-Location $tempDir
    }
}

Write-Host "Migration completed!"
