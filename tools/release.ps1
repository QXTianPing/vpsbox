[CmdletBinding()]
param(
    [switch]$Bump
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[INFO] $Message"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Command
    )

    Write-Info $Name
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name 失败，退出码：$LASTEXITCODE"
    }
}

function Get-VersionFromText {
    param([Parameter(Mandatory)][string]$Text)

    $matches = [regex]::Matches(
        $Text,
        '(?m)^VPSBOX_VERSION="(v[0-9]+\.[0-9]+\.[0-9]+)"\r?$'
    )
    if ($matches.Count -ne 1) {
        throw 'vpsbox.sh 必须且只能包含一个格式正确的 VPSBOX_VERSION。'
    }
    return $matches[0].Groups[1].Value
}

function Get-NextPatchVersion {
    param([Parameter(Mandatory)][string]$Version)

    if ($Version -notmatch '^v([0-9]+)\.([0-9]+)\.([0-9]+)$') {
        throw "版本号格式不正确：$Version"
    }
    return 'v{0}.{1}.{2}' -f
        [int]$Matches[1],
        [int]$Matches[2],
        ([int]$Matches[3] + 1)
}

function Get-HeadVersion {
    $headText = (& git show HEAD:vpsbox.sh 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw '无法读取 HEAD 中的 vpsbox.sh。'
    }
    return Get-VersionFromText -Text $headText
}

function Get-WorkingTreeChanges {
    [array]$changes = @(& git status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0) {
        throw '无法读取 Git 工作区状态。'
    }
    return $changes
}

function Update-VersionIfNeeded {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$CurrentText,
        [Parameter(Mandatory)][string]$CurrentVersion,
        [Parameter(Mandatory)][string]$HeadVersion
    )

    $expectedVersion = Get-NextPatchVersion -Version $HeadVersion

    if ($CurrentVersion -eq $expectedVersion) {
        Write-Info "版本已经是相对 HEAD 的下一补丁版本：$CurrentVersion"
        return $CurrentText
    }
    if ($CurrentVersion -ne $HeadVersion) {
        throw "当前版本 $CurrentVersion 既不等于 HEAD 的 $HeadVersion，也不是下一版本 $expectedVersion。"
    }

    $updatedText = [regex]::Replace(
        $CurrentText,
        '(?m)^VPSBOX_VERSION="[^"]+"\r?$',
        "VPSBOX_VERSION=`"$expectedVersion`""
    )
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($ScriptPath, $updatedText, $utf8NoBom)
    Write-Info "版本已更新：$CurrentVersion -> $expectedVersion"
    return $updatedText
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scriptPath = Join-Path $repoRoot 'vpsbox.sh'
$testsPath = Join-Path $repoRoot 'tests'

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $testsPath -PathType Container)) {
    throw '仓库结构不完整，找不到 vpsbox.sh 或 tests 目录。'
}

Push-Location $repoRoot
try {
    foreach ($commandName in 'git', 'shellcheck') {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw "未找到依赖：$commandName"
        }
    }

    $scriptText = [IO.File]::ReadAllText($scriptPath)
    $currentVersion = Get-VersionFromText -Text $scriptText
    $headVersion = Get-HeadVersion
    if ($Bump) {
        $scriptText = Update-VersionIfNeeded `
            -ScriptPath $scriptPath `
            -CurrentText $scriptText `
            -CurrentVersion $currentVersion `
            -HeadVersion $headVersion
        $currentVersion = Get-VersionFromText -Text $scriptText
    }
    [array]$workingTreeChanges = @(Get-WorkingTreeChanges)
    if ($workingTreeChanges.Count -gt 0) {
        $expectedVersion = Get-NextPatchVersion -Version $headVersion
        if ($currentVersion -ne $expectedVersion) {
            throw "检测到待发布改动，版本必须由 $headVersion 增加至 $expectedVersion。请运行：.\tools\release.ps1 -Bump"
        }
    }

    $shellScripts = @($scriptPath) +
        @(Get-ChildItem -LiteralPath $testsPath -Filter '*.sh' -File |
            Sort-Object FullName |
            ForEach-Object FullName)
    Invoke-Native -Name '运行 ShellCheck warning 级检查' -Command {
        & shellcheck --severity=warning @shellScripts
    }

    $gitCommand = Get-Command git
    $gitBashCandidates = @(
        (Join-Path (Split-Path $gitCommand.Source -Parent) '..\bin\bash.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
    )
    $gitBash = $gitBashCandidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $gitBash) {
        throw '未找到 Git for Windows 自带的 bash.exe。'
    }
    $bashRepoRoot = $repoRoot.Replace('\', '/')
    $quotedBashRoot = "'" + $bashRepoRoot.Replace("'", "'\''") + "'"
    $bashCommand = "cd $quotedBashRoot && bash -n vpsbox.sh tests/*.sh"
    Invoke-Native -Name '使用本地 Git Bash 运行 Bash 语法检查' -Command {
        & $gitBash -lc $bashCommand
    }

    Invoke-Native -Name '检查未暂存 Git 差异格式' -Command {
        & git diff --check
    }
    Invoke-Native -Name '检查已暂存 Git 差异格式' -Command {
        & git diff --cached --check
    }

    [array]$conflicts = @(& git diff --name-only --diff-filter=U) +
        @(& git diff --cached --name-only --diff-filter=U)
    if ($conflicts.Count -gt 0) {
        throw "存在尚未解决的 Git 冲突：$($conflicts -join ', ')"
    }

    $selfRelativePath = 'tools/release.ps1'
    & git ls-files --error-unmatch -- $selfRelativePath >$null 2>&1
    $selfTrackedExitCode = $LASTEXITCODE
    if ($selfTrackedExitCode -notin 0, 1) {
        throw "无法判断 $selfRelativePath 的跟踪状态，退出码：$selfTrackedExitCode"
    }
    $selfIsTracked = $selfTrackedExitCode -eq 0

    [array]$untracked = @(
        @(& git ls-files --others --exclude-standard) |
            Where-Object { $_ -ne $selfRelativePath }
    )
    if ($LASTEXITCODE -ne 0) {
        throw '无法读取未跟踪文件列表。'
    }
    if ($untracked.Count -gt 0) {
        throw "存在未跟踪文件，请确认后再发布：$($untracked -join ', ')"
    }
    if (-not $selfIsTracked) {
        [array]$selfDiffCheck = @(
            & git -c core.autocrlf=false diff --no-index --check -- NUL $selfRelativePath 2>&1
        )
        $selfDiffExitCode = $LASTEXITCODE
        if ($selfDiffExitCode -notin 0, 1) {
            throw "$selfRelativePath 格式检查执行失败，退出码：$selfDiffExitCode"
        }
        if ($selfDiffCheck.Count -gt 0) {
            throw "$selfRelativePath 存在差异格式问题：$($selfDiffCheck -join '; ')"
        }
    }

    $sensitivePattern =
        'BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}'
    & git grep -n -I -E $sensitivePattern -- .
    $grepExitCode = $LASTEXITCODE
    if ($grepExitCode -eq 0) {
        throw '检测到疑似私钥或 GitHub Token，请先检查。'
    }
    if ($grepExitCode -ne 1) {
        throw "敏感信息检查执行失败，退出码：$grepExitCode"
    }
    if (-not $selfIsTracked) {
        & git grep --no-index -n -I -E $sensitivePattern -- $selfRelativePath
        $selfGrepExitCode = $LASTEXITCODE
        if ($selfGrepExitCode -eq 0) {
            throw "$selfRelativePath 检测到疑似私钥或 GitHub Token，请先检查。"
        }
        if ($selfGrepExitCode -ne 1) {
            throw "$selfRelativePath 敏感信息检查执行失败，退出码：$selfGrepExitCode"
        }
    }
    $global:LASTEXITCODE = 0

    Write-Info "发布前检查全部通过，当前版本：$currentVersion"
    Write-Info '本脚本没有执行提交或推送。'
}
finally {
    Pop-Location
}
