#!/bin/bash

#!/bin/bash

# --- Auto-Download Toolchain Logic ---
# Mendeteksi jika berjalan di GitHub Actions atau folder toolchain tidak ada
if [ ! -d "$HOME/android/toolchains" ]; then
    echo "Toolchains not found! Preparing to download..."
    mkdir -p $HOME/android/toolchains
    mkdir -p $HOME/android/Anykernel3

    # 1. Download AOSP Clang (Contoh: versi r450784d, sesuaikan jika perlu)
    if [ ! -d "$HOME/android/toolchains/aosp-clang" ]; then
        echo "Downloading Clang..."
        wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r450784d.tar.gz -O clang.tar.gz
        mkdir -p $HOME/android/toolchains/aosp-clang
        tar -xf clang.tar.gz -C $HOME/android/toolchains/aosp-clang
        rm clang.tar.gz
    fi

    # 2. Download GCC 64 (Aarch64)
    if [ ! -d "$HOME/android/toolchains/llvm-arm64" ]; then
        echo "Downloading GCC 64..."
        git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git $HOME/android/toolchains/llvm-arm64
    fi

    # 3. Download GCC 32 (Arm)
    if [ ! -d "$HOME/android/toolchains/llvm-arm" ]; then
        echo "Downloading GCC 32..."
        git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git $HOME/android/toolchains/llvm-arm
    fi

    # 4. Download AnyKernel3 (Wajib ada karena dipanggil di package_kernel)
    if [ -z "$(ls -A $HOME/android/Anykernel3)" ]; then
        echo "Downloading AnyKernel3..."
        # Ganti URL ini dengan repo AnyKernel3 khusus device Anda (Ginkgo)
        git clone https://github.com/osm0sis/AnyKernel3.git $HOME/android/Anykernel3
    fi
fi

# --- Original Variable Definitions (Sekarang Aman) ---
TC_DIR="$HOME/android/toolchains/aosp-clang"
GCC_64_DIR="$HOME/android/toolchains/llvm-arm64"
GCC_32_DIR="$HOME/android/toolchains/llvm-arm"
AK3_DIR="$HOME/android/Anykernel3"
DEFCONFIG="vendor/ginkgo-perf_defconfig"

# ... sisa script ke bawah tetap sama ...

# Function to handle script cleanup on exit or interrupt
cleanup() {
    echo -e "\nScript interrupted! Performing cleanup..."
    rm -rf out/arch/arm64/boot 2>/dev/null
    echo "Temporary files cleaned up."
    echo "Exiting..."
}

# Set trap to call the cleanup function on EXIT or SIGINT (Ctrl+C)
trap cleanup EXIT SIGINT

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --regen       Regenerate defconfig and save it to the configuration directory"
    echo "  -c, --clean       Clean the output directory"
    echo "  -g, --get-ksu     Download and set up KernelSU, apply patch, and modify defconfig"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "If no options are provided, the script will proceed to compile the kernel and package it."
    echo "The script will also adjust the output ZIP name based on the presence of the KernelSU directory."
    echo ""
    echo "Example:"
    echo "  $0           # Compile kernel"
    echo "  $0 --regen   # Regenerate defconfig"
    echo "  $0 --clean   # Clean output directory"
    echo "  $0 --get-ksu # Download and set up KernelSU"
}

# Function to start the timer
start_timer() {
    START_TIME=$(date +%s)  # Get the current time in seconds since epoch
}

# Function to end the timer and display elapsed time
end_timer() {
    END_TIME=$(date +%s)  # Get the end time
    ELAPSED_TIME=$(( END_TIME - START_TIME ))  # Calculate elapsed time in seconds

    # Convert seconds to minutes and seconds
    MINUTES=$(( ELAPSED_TIME / 60 ))
    SECONDS=$(( ELAPSED_TIME % 60 ))

    echo -e "\nCompleted in ${MINUTES} minute(s) and ${SECONDS} second(s)!"
}

# Function to determine the ZIP file name based on the presence of KernelSU and date
get_zip_name() {
    local head date
    head=$(git rev-parse --short=7 HEAD)
    date=$(date +%Y%m%d)  # Get the current date in YYYYMMDD format
  
    if [[ -d "KernelSU" ]]; then
        ZIPNAME="Cryo-ginkgo-ksu-${head}-${date}.zip"
    else
        ZIPNAME="Cryo-ginkgo-${head}-${date}.zip"
    fi

    echo "$ZIPNAME"
}

# Function to download and set up KernelSU, apply patch and modify defconfig
set_kernelsu() {
    echo "Downloading and setting up KernelSU-Next (Latest)..."
    
    # Menggunakan repo rifsxd (KernelSU-Next) branch 'next'
    curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next
    
    if [[ $? -eq 0 ]]; then
        echo "KernelSU-Next downloaded and set up successfully."
        
        # KernelSU-Next mungkin membuat folder bernama 'KernelSU' atau 'KernelSU-Next'
        if [[ -d "KernelSU" ]] || [[ -d "KernelSU-Next" ]]; then
            
            # Cek dan apply patch manual hanya jika file patch ada
            if [[ -f "ksu_hook.patch" ]]; then
                echo "Applying KernelSU-hook.patch..."
                git apply ksu_hook.patch || echo "Patch failed or already applied, skipping..."
            fi
            
            # Mengaktifkan CONFIG_KSU di defconfig
            # Menangani dua kemungkinan default config (not set atau =n)
            echo "Enabling CONFIG_KSU in $DEFCONFIG..."
            sed -i 's/# CONFIG_KSU is not set/CONFIG_KSU=y/g' "arch/arm64/configs/$DEFCONFIG"
            sed -i 's/CONFIG_KSU=n/CONFIG_KSU=y/g' "arch/arm64/configs/$DEFCONFIG"
            
            echo "CONFIG_KSU enabled in $DEFCONFIG."
        else
            echo "KernelSU directory not found after download!"
        fi
    else
        echo "Failed to download KernelSU-Next."
        exit 1
    fi
}

# Function to regenerate defconfig
regen_defconfig() {
    make O=out ARCH=arm64 "$DEFCONFIG" savedefconfig
    cp out/defconfig "arch/arm64/configs/$DEFCONFIG"
    echo "Defconfig regenerated and saved!"
}

# Function to clean the output directory
clean_output() {
    rm -rf out
    echo "Output directory cleaned."
}

# Fungsi Kirim ke Telegram
push_to_telegram() {
    local file_path="$1"
    local caption="$2"
    
    # Cek apakah Token dan Chat ID ada
    if [[ -z "$TG_TOKEN" || -z "$TG_CHAT_ID" ]]; then
        echo "Telegram Token or Chat ID not set. Skipping upload."
        return
    fi

    if [[ -f "$file_path" ]]; then
        echo "Uploading to Telegram..."
        curl -F chat_id="${TG_CHAT_ID}" \
             -F document=@"${file_path}" \
             -F caption="${caption}" \
             "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" > /dev/null 2>&1
        
        if [[ $? -eq 0 ]]; then
            echo "Upload successful!"
        else
            echo "Upload failed!"
        fi
    else
        echo "File to upload not found: $file_path"
    fi
}

# Function to set up output directory and build kernel using a make command stored in an array
setup_and_compile() {
    mkdir -p out
    make O=out ARCH=arm64 "$DEFCONFIG"
    
    echo -e "\nStarting compilation...\n"
    local jobs
    jobs=$(nproc 2>/dev/null || echo 4)

    # Array holding the make arguments
    make_args=(
        -j$((jobs + 1))
        O=out
        ARCH=arm64
        CC=clang
        LD=ld.lld
        AR=llvm-ar
        AS=llvm-as
        NM=llvm-nm
        OBJCOPY=llvm-objcopy
        OBJDUMP=llvm-objdump
        STRIP=llvm-strip
        CROSS_COMPILE="$GCC_64_DIR/bin/aarch64-linux-android-"
        CROSS_COMPILE_ARM32="$GCC_32_DIR/bin/arm-linux-androideabi-"
        CLANG_TRIPLE=aarch64-linux-gnu-
        Image.gz-dtb
        dtbo.img
    )

    # Invoke make with the arguments from the array
    make "${make_args[@]}"
    
    if [[ -f "out/arch/arm64/boot/Image.gz-dtb" && -f "out/arch/arm64/boot/dtbo.img" ]]; then
        echo -e "\nKernel compiled successfully!"
        package_kernel
    else
        echo -e "\nCompilation failed!"
        exit 1
    fi
}

# Function to package kernel into a zip file
package_kernel() {
    local zip_name
    zip_name=$(get_zip_name)
  
    if [[ -d "$AK3_DIR" ]]; then
        # Copy Image.gz-dtb dan dtbo.img ke folder AnyKernel3
        cp out/arch/arm64/boot/Image.gz-dtb "$AK3_DIR"
        cp out/arch/arm64/boot/dtbo.img "$AK3_DIR"
        
        # Masuk ke direktori AnyKernel3
        cd "$AK3_DIR" || { echo "Failed to enter AnyKernel3 directory!"; exit 1; }
        
        # ZIP isinya
        echo "Zipping kernel..."
        zip -r9 "../$zip_name" * -x '*.git*' README.md *placeholder
        
        # --- PERBAIKAN UTAMA DI SINI ---
        # Pindahkan file ZIP dari folder $HOME/android ke folder kerja saat ini (Repository Root)
        mv "../$zip_name" "$GITHUB_WORKSPACE/$zip_name" 2>/dev/null || mv "../$zip_name" "../../$zip_name"
        
        cd - || exit 1
        
        rm -rf out/arch/arm64/boot
        echo -e "\nKernel packaged successfully as: $zip_name"
        
        # Debugging: Tampilkan lokasi file sekarang
        ls -l "$zip_name"
        
        end_timer
    else
        echo "AnyKernel3 directory not found!"
        exit 1
    fi
}

# Main function to control script flow
main() {
    start_timer  # Start the timer
    case "$1" in
        -r|--regen)
            regen_defconfig
            ;;
        -c|--clean)
            clean_output
            ;;
        -g|--get-ksu)
            set_kernelsu
            ;;
        -h|--help)
            show_help
            ;;
        *)
            if [[ -n "$1" ]]; then
                echo "Unknown option: $1"
                show_help
                exit 1
            fi
            setup_and_compile
            ;;
    esac
}

# Run the main function
main "$@"
