@echo off
setlocal EnableDelayedExpansion

:: ============================================================
::  Automated WSL2 + Ubuntu 24.04 + ROS 2 Iron + Gazebo
::  Harmonic + PX4 SITL installer
::
::  Usage: right-click, Run as Administrator
::  A reboot is required between phase 1 and phase 2.
:: ============================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo This script must be run as Administrator.
    echo Right-click the file and choose "Run as administrator".
    pause
    exit /b 1
)

echo.
echo ============================================
echo   ROS 2 Iron + Gazebo Harmonic + PX4 setup
echo ============================================
echo.

:: Detect whether Ubuntu is already installed
wsl -d Ubuntu-24.04 -e true >nul 2>&1
if %errorLevel% equ 0 goto :phase2

:: ------------------------------------------------------------
::  Phase 1 - install WSL2 and Ubuntu
:: ------------------------------------------------------------
echo [Phase 1] Installing WSL2 and Ubuntu 24.04...
echo.

wsl --install -d Ubuntu-24.04
if %errorLevel% neq 0 (
    echo.
    echo WSL install failed. If your Windows build is older than 2004,
    echo install WSL manually: https://learn.microsoft.com/windows/wsl/install
    pause
    exit /b 1
)

echo.
echo ------------------------------------------------------------
echo  Reboot required.
echo.
echo  After rebooting:
echo    1. Launch Ubuntu 24.04 from the Start menu
echo    2. Create your username and password when prompted
echo    3. Run this script again as Administrator
echo ------------------------------------------------------------
echo.
pause
exit /b 0

:: ------------------------------------------------------------
::  Phase 2 - provision the Ubuntu environment
:: ------------------------------------------------------------
:phase2
echo [Phase 2] Ubuntu detected. Provisioning environment...
echo.
echo This will take 30-60 minutes. PX4's build is the slow part.
echo.
pause

set "SETUP=%TEMP%\ros2_setup.sh"
if exist "%SETUP%" del "%SETUP%"

:: Write the provisioning script with Unix line endings.
:: Everything below runs inside Ubuntu, not in cmd.
>"%SETUP%" (
echo #!/usr/bin/env bash
echo set -euo pipefail
echo.
echo echo "==^> Updating system packages"
echo sudo apt-get update
echo sudo apt-get upgrade -y
echo sudo apt-get install -y build-essential cmake git wget curl vim gnupg2 \
echo     lsb-release unzip software-properties-common locales
echo.
echo echo "==^> Configuring locale"
echo sudo locale-gen en_US en_US.UTF-8
echo sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
echo export LANG=en_US.UTF-8
echo.
echo echo "==^> Adding ROS 2 apt repository"
echo sudo mkdir -p /usr/share/keyrings
echo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc ^| \
echo     gpg --dearmor ^| sudo tee /usr/share/keyrings/ros-archive-keyring.gpg ^> /dev/null
echo CODENAME=$^(lsb_release -cs^)
echo echo "deb [arch=$^(dpkg --print-architecture^) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${CODENAME} main" ^| \
echo     sudo tee /etc/apt/sources.list.d/ros2.list ^> /dev/null
echo.
echo echo "==^> Installing ROS 2 Iron"
echo sudo apt-get update
echo sudo apt-get install -y ros-iron-desktop python3-colcon-common-extensions python3-rosdep
echo.
echo echo "==^> Adding Gazebo apt repository"
echo curl -sSL https://packages.osrfoundation.org/gazebo.key ^| \
echo     gpg --dearmor ^| sudo tee /usr/share/keyrings/gazebo-archive-keyring.gpg ^> /dev/null
echo echo "deb [signed-by=/usr/share/keyrings/gazebo-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable ${CODENAME} main" ^| \
echo     sudo tee /etc/apt/sources.list.d/gazebo-stable.list ^> /dev/null
echo.
echo echo "==^> Installing Gazebo Harmonic and the ROS-Gazebo bridge"
echo sudo apt-get update
echo sudo apt-get install -y gz-harmonic ros-iron-ros-gz ros-iron-ros-gz-bridge
echo.
echo echo "==^> Installing MAVROS"
echo sudo apt-get install -y ros-iron-mavros ros-iron-mavros-extras geographiclib-tools
echo sudo geographiclib-get-geoids egm96-5
echo sudo geographiclib-get-magnetic wmm2020
echo sudo geographiclib-get-gravity egm96
echo if [ ! -d /usr/local/share/GeographicLib ]; then
echo     sudo ln -s /usr/share/GeographicLib /usr/local/share/GeographicLib ^|^| true
echo fi
echo.
echo echo "==^> Creating colcon workspace"
echo mkdir -p ~/ros2_ws/src
echo cd ~/ros2_ws
echo source /opt/ros/iron/setup.bash
echo colcon build --symlink-install
echo.
echo echo "==^> Initializing rosdep"
echo sudo rosdep init ^|^| true
echo rosdep update
echo.
echo echo "==^> Cloning and building PX4 Autopilot"
echo cd ~
echo if [ ! -d ~/PX4-Autopilot ]; then
echo     git clone https://github.com/PX4/PX4-Autopilot.git --recursive
echo fi
echo cd ~/PX4-Autopilot
echo bash ./Tools/setup/ubuntu.sh --no-nuttx --no-sim-tools
echo make px4_sitl_default
echo.
echo echo "==^> Writing shell environment"
echo BRC=~/.bashrc
echo grep -qxF 'source /opt/ros/iron/setup.bash' $BRC ^|^| echo 'source /opt/ros/iron/setup.bash' ^>^> $BRC
echo grep -qxF 'source ~/ros2_ws/install/setup.bash' $BRC ^|^| echo 'source ~/ros2_ws/install/setup.bash' ^>^> $BRC
echo grep -qxF 'export GZ_VERSION=harmonic' $BRC ^|^| echo 'export GZ_VERSION=harmonic' ^>^> $BRC
echo grep -qxF 'export ROS_PACKAGE_PATH=$ROS_PACKAGE_PATH:$HOME/PX4-Autopilot' $BRC ^|^| \
echo     echo 'export ROS_PACKAGE_PATH=$ROS_PACKAGE_PATH:$HOME/PX4-Autopilot' ^>^> $BRC
echo grep -qxF 'export GZ_SIM_RESOURCE_PATH=$GZ_SIM_RESOURCE_PATH:$HOME/PX4-Autopilot/Tools/simulation/gz/resources' $BRC ^|^| \
echo     echo 'export GZ_SIM_RESOURCE_PATH=$GZ_SIM_RESOURCE_PATH:$HOME/PX4-Autopilot/Tools/simulation/gz/resources' ^>^> $BRC
echo.
echo echo "==^> Fixing WSL runtime directory permissions"
echo if [ -d "/run/user/$^(id -u^)" ]; then chmod 700 "/run/user/$^(id -u^)"; fi
echo.
echo echo ""
echo echo "Done. Close this terminal, reopen Ubuntu, then try:"
echo echo "  gz sim"
echo echo "  cd ~/PX4-Autopilot ^&^& make px4_sitl_default none"
)

:: Convert CRLF to LF so bash can read it
wsl -d Ubuntu-24.04 -e bash -c "sed 's/\r$//' '$(wslpath '%SETUP%')' > ~/ros2_setup.sh && chmod +x ~/ros2_setup.sh"

echo.
echo Running provisioning script inside Ubuntu...
echo You will be prompted for your Ubuntu password.
echo.

wsl -d Ubuntu-24.04 -e bash -lc "~/ros2_setup.sh"
set RESULT=%errorLevel%

del "%SETUP%" 2>nul
wsl -d Ubuntu-24.04 -e rm -f ~/ros2_setup.sh 2>nul

echo.
if %RESULT% equ 0 (
    echo ============================================
    echo   Installation complete.
    echo ============================================
    echo.
    echo Open Ubuntu and test with:
    echo   gz sim
    echo   cd ~/PX4-Autopilot ^&^& make px4_sitl_default none
) else (
    echo Provisioning exited with error code %RESULT%.
    echo Scroll up to find the failing step and rerun this script.
)
echo.
pause
endlocal
