<#
.SYNOPSIS
批量删除 GitHub 仓库（需谨慎操作，删除不可逆）

.DESCRIPTION
从指定文件读取仓库列表（格式：owner/仓库名），通过 GitHub API 批量删除，包含多重确认和存在性校验
#>

# ==============================================
# 配置参数（请根据实际情况修改）
# ==============================================
$token = "XXXXXXX"  # 你的 GitHub 个人访问令牌（必须包含 delete_repo 权限）
$repoListFile = "repos_to_delete.txt"  # 存储仓库列表的文件路径（相对或绝对路径）
# ==============================================

# 检查令牌是否为空
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "请先配置 GitHub 个人访问令牌（PAT）"
    exit 1
}

# 检查仓库列表文件是否存在
if (-not (Test-Path $repoListFile -PathType Leaf)) {
    Write-Error "仓库列表文件 $repoListFile 不存在不存在，请检查路径"
    exit 1
}

# 读取仓库列表（格式：owner/repo，忽略空行和注释行）
$repoList = Get-Content $repoListFile | Where-Object {
    $_ -match '\S' -and -not $_ -match '^#'  # 过滤空行和以 # 开头的注释行
}

# 检查仓库列表是否为空
if ($repoList.Count -eq 0) {
    Write-Error "仓库列表文件 $repoListFile 中未找到有效仓库信息"
    exit 1
}

# 显示待删除的仓库列表，供用户确认
Write-Host "`n===== 待删除的仓库列表（共 $($repoList.Count) 个） =====" -ForegroundColor Yellow
$repoList | ForEach-Object { Write-Host " - $_" }

# 一级确认：是否继续操作
$confirm1 = Read-Host "`n上述仓库将被永久删除（不可逆），是否继续？(输入 'yes' 进入下一步)"
if ($confirm1 -ne "yes") {
    Write-Host "`n操作已取消。" -ForegroundColor Green
    exit 0
}

# 二级确认：输入特定字符串确认
$confirm2 = Read-Host "`n请输入 'DELETE ALL' 确认删除所有仓库（区分大小写）"
if ($confirm2 -ne "DELETE ALL") {
    Write-Host "`n输入不匹配，操作已取消。" -ForegroundColor Green
    exit 0
}

# 配置 API 请求头
$headers = @{
    "Authorization" = "token $token"
    "Accept"        = "application/vnd.github.v3+json"
}

# 批量删除仓库（带存在性校验）
$successCount = 0
$failCount = 0
$failList = @()

Write-Host "`n===== 开始删除仓库 =====" -ForegroundColor Cyan

foreach ($repo in $repoList) {
    # 拆分 owner 和 repo 名称（格式必须为 owner/repo）
    $parts = $repo -split "/", 2
    if ($parts.Count -ne 2) {
        Write-Warning "仓库格式错误：$repo（正确格式：owner/仓库名），跳过"
        $failCount++
        $failList += @{ repo = $repo; reason = "格式错误" }
        continue
    }
    $owner = $parts[0]
    $repoName = $parts[1]
    $apiUrl = "https://api.github.com/repos/$owner/$repoName"

    try {
        # 先校验仓库是否存在（发送 GET 请求）
        Write-Host "`n正在校验仓库：$repo..." -ForegroundColor Gray
        $check = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -ErrorAction Stop
        Write-Host "仓库 $repo 存在，准备删除..." -ForegroundColor DarkYellow

        # 执行删除操作（发送 DELETE 请求）
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Delete -ErrorAction Stop
        $successCount++
        Write-Host "✅ 仓库 $repo 已成功删除" -ForegroundColor Green
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        $errorMsg = $_.ErrorDetails.Message
        $failCount++
        $failList += @{ repo = $repo; reason = "状态码：$statusCode，错误：$errorMsg" }
        
        if ($statusCode -eq 404) {
            Write-Host "❌ 仓库 $repo 不存在（可能已删除）" -ForegroundColor Red
        }
        elseif ($statusCode -eq 403) {
            Write-Host "❌ 无权限删除仓库 $repo（检查令牌权限或仓库所有权）" -ForegroundColor Red
        }
        else {
            Write-Host "❌ 删除仓库 $repo 失败：$errorMsg" -ForegroundColor Red
        }
    }
}  # 修复：补充 foreach 循环的闭合 }

# 输出删除结果总结
Write-Host "`n===== 删除结果总结 =====" -ForegroundColor Yellow
Write-Host "总计：$($repoList.Count) 个仓库"
Write-Host "成功删除：$successCount 个" -ForegroundColor Green
Write-Host "删除失败：$failCount 个" -ForegroundColor Red

if ($failList.Count -gt 0) {
    Write-Host "`n失败详情：" -ForegroundColor Red
    $failList | ForEach-Object {
        Write-Host " - $($_.repo)：$($_.reason)"
    }
}  # 修复：补充 if 语句的闭合 }

Write-Host "`n操作完成。" -ForegroundColor Cyan
