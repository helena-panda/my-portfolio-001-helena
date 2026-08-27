@echo off
title 作品集一键上传 - GitHub

rem ==================== 配置区（按需修改） ====================
set "GH_USER=helena-panda"
set "REPO=my-portfolio-001-helena"
set "BRANCH=main"
set "MAX_TRY=5"
rem ==========================================================

echo.
echo ============================================================
echo   南昌大学·人机协同备课课程   作品集一键上传助手
echo   作者：helena   学号：001   专业：Physics
echo ============================================================
echo.

rem ------ 1. 检测 Git ------
where git >nul 2>nul
if not %errorlevel%==0 (
    echo [错误] 未找到 Git，请先安装 Git for Windows 后重试。
    pause
    exit /b 1
)

rem ------ 2. 若是全新文件夹，先初始化仓库 ------
if exist ".git" goto :init_done
echo [1/5] 首次运行：正在初始化 Git 仓库...
git init >nul
git branch -M %BRANCH%
git config user.name "helena"
git config user.email "helena-panda@users.noreply.github.com"
:init_done

rem ------ 3. 补齐缺省脚手架文件（内容保持英文以免编码乱码） ------
if exist ".gitignore" goto :gi_done
(
echo # temp
echo ~$*
echo Thumbs.db
echo Desktop.ini
echo .DS_Store
echo node_modules/
echo .vscode/
echo __pycache__/
) > .gitignore
:gi_done

if exist "README.md" goto :readme_done
(
echo # %REPO%
echo.
echo Nanchang University - Human-AI Collaboration Portfolio
echo Student: helena  /  ID: 001  /  Major: Physics
echo See README.md of the main repo for the full 16-week index.
) > README.md
:readme_done

echo [1/5] 环境就绪，开始扫描改动...

rem ------ 4. 暂存并提交改动 ------
git add -A
git diff --cached --quiet
if %errorlevel%==0 goto :no_commit
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm'"') do set "TS=%%i"
git commit -m "update: portfolio sync %TS%" >nul
if not %errorlevel%==0 (
    echo [错误] 提交失败，请检查 Git 用户配置。
    pause
    exit /b 1
)
echo [2/4] 已提交本次改动：%TS%
goto :commit_done
:no_commit
echo [2/4] 没有检测到新改动，跳过提交。
:commit_done

rem ------ 5. 配置远程并推送（失败自动重试） ------
git remote get-url origin >nul 2>nul
if %errorlevel%==0 goto :remote_ok
git remote add origin https://github.com/%GH_USER%/%REPO%.git
:remote_ok

echo [3/4] 正在推送到 GitHub（网络较慢时请耐心等待）...
set "TRY_NUM=0"
:push_retry
set /a TRY_NUM+=1
git push -u origin %BRANCH%
if not %errorlevel%==0 (
    if %TRY_NUM% LSS %MAX_TRY% (
        echo [提示] 第 %TRY_NUM% 次推送失败，网络可能不稳定，10 秒后自动重试...
        timeout /t 10 /nobreak >nul
        goto :push_retry
    )
    echo [错误] 连续 %MAX_TRY% 次推送失败。请检查：
    echo        1. 网络是否可访问 GitHub（或在 GitHub 登录过）
    echo        2. 若装过代理软件（如 Clash），先开启代理再重跑脚本
    pause
    exit /b 1
)

echo [4/4] 全部完成！你的作品已同步到云端。
echo.
echo        作品集地址：https://github.com/%GH_USER%/%REPO%
echo.
pause