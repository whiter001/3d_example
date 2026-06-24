#!/usr/bin/env nu
# =============================================================================
#  build.nu - yie_ar_kungfu 构建脚本
# =============================================================================
#
#  用法:
#    nu build.nu debug            构建 debug 版本 (含调试符号, 不优化)
#    nu build.nu prod             构建 prod 版本 (Release-fast, 默认目标)
#    nu build.nu build [mode]     同上, 但显式指定 (mode 默认为 prod)
#    nu build.nu run [mode]       构建并启动游戏 (mode 默认为 prod)
#    nu build.nu clean            删除所有编译产物
#    nu build.nu stats            显示项目统计 (代码行数 / 资源数量)
#
#  产物:
#    yie_ar_kungfu          - prod 构建
#    yie_ar_kungfu_debug    - debug 构建
#
#  注意:
#    - V 0.5.x 需要 -enable-globals 标志才能用 __global (后续 V 版本会成为默认)
#    - V 0.5.x 的 raylib 绑定与 raylib 5.x 头文件存在 `ctx_data` vs `ctxData`
#      字段名不匹配, 启用 -prod 会触发 C 编译错误. 本脚本的 prod 模式用 V
#      默认的 Release-fast 优化 (不带 -prod).
# =============================================================================

# ---- 常量 --------------------------------------------------------------------
#
#  注意: V 0.5.x 的 raylib 绑定与系统 raylib 5.x 头文件存在 `ctx_data` vs
#  `ctxData` 字段名不匹配, 启用 -prod 时会触发 C 编译错误. 因此 prod 模式
#  用 V 默认的优化级别 (Release-fast), 而不是 -prod.
#  debug 模式加 -g 保留调试符号.
# ------------------------------------------------------------------------------
const prod_output  = "yie_ar_kungfu"
const debug_output = "yie_ar_kungfu_debug"
const prod_args    = ["-enable-globals"]
const debug_args   = ["-enable-globals", "-g"]

# ---- 默认入口 -----------------------------------------------------------------
def main [] {
    build
}

# ---- 子命令 -------------------------------------------------------------------
def "main debug" [] {
    do_build "debug"
}

def "main prod" [] {
    do_build "prod"
}

def "main build" [mode: string = "prod"] {
    do_build $mode
}

def "main run" [mode: string = "prod"] {
    do_build $mode
    let exe = (output_for $mode)
    print $"==> 启动 ($exe)"
    ^$exe
}

def "main clean" [] {
    for target in [$prod_output, $debug_output] {
        if ($target | path exists) {
            rm $target
            print $"removed ($target)"
        }
        let dsym = $"($target).dSYM"
        if ($dsym | path exists) {
            rm -r $dsym
            print $"removed ($dsym)/"
        }
    }
}

def "main stats" [] {
    print "==== yie_ar_kungfu stats ===="
    let v_files = (ls *.v)
    let total = ($v_files | get size | math sum)
    let lines = (
        $v_files
        | each { |f| ($f.name | path expand | open --raw | lines | length) }
        | math sum
    )
    print $"V 源文件:  ($v_files | length) 个"
    print $"总大小:    ($total)"
    print $"总行数:    ($lines)"
    for f in $v_files {
        let n = ($f.name | path expand | open --raw | lines | length)
        print $"  - ($f.name): ($n) 行"
    }
    let pngs = (ls assets/images/*.png | length)
    let wavs = (ls assets/sounds/*.wav | length)
    print $"图片资源:  ($pngs) 张"
    print $"音频资源:  ($wavs) 个"
}

# ---- 内部函数 -----------------------------------------------------------------
def output_for [mode: string] {
    if $mode == "debug" { $debug_output } else { $prod_output }
}

def args_for [mode: string] {
    if $mode == "debug" { $debug_args } else { $prod_args }
}

def do_build [mode: string] {
    let exe     = (output_for $mode)
    let vflags  = (args_for $mode)
    let cmd_str = (["v", ...$vflags, ".", "-o", $exe] | str join " ")

    print $"==> 构建 ($mode) 模式"
    print $"    命令: ($cmd_str)"

    # 在项目目录里跑 v; build.nu 与 .v 文件同目录, 直接 cd 到脚本所在目录
    let cwd = ($env.FILE_PWD? | default ".")
    cd $cwd
    ^v ...$vflags . -o $exe

    if not ($exe | path exists) {
        error make {msg: $"构建失败: 未生成 ($exe)"}
    }

    let info = (ls $exe | first)
    print $"==> 完成: ($exe)  ($info.size)"
}

# 让 `nu build.nu` (无参数) 等价于 `nu build.nu prod`
def build [] {
    do_build "prod"
}