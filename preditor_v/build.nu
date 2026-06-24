#!/usr/bin/env nu
# =============================================================================
#  build.nu - preditor_v 构建脚本
# =============================================================================
#
#  用法:
#    nu build.nu debug            构建 debug 版本
#    nu build.nu prod             构建 prod 版本 (默认)
#    nu build.nu build [mode]     显式指定 (mode 默认为 prod)
#    nu build.nu run [mode]       构建并启动
#    nu build.nu clean            删除所有产物 + dSYM
#    nu build.nu stats            代码行数 / 资源数量
#
#  产物:
#    preditor_v          - prod
#    preditor_v_debug    - debug
#
#  注意:
#    - V 0.5.x 需要 -enable-globals 才能用 __global
#    - V 0.5.x raylib 绑定与 raylib 5.x 头文件 ctx_data 字段不匹配, 不支持 -prod
# =============================================================================

const prod_output  = "preditor_v"
const debug_output = "preditor_v_debug"
const prod_args    = ["-enable-globals"]
const debug_args   = ["-enable-globals", "-g"]

def main [] {
    build
}

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
    print "==== preditor_v stats ===="
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
    let fonts = (ls assets/fonts/*.ttf | length)
    print $"字体资源:  ($fonts) 个"
}

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

    let cwd = ($env.FILE_PWD? | default ".")
    cd $cwd
    ^v ...$vflags . -o $exe

    if not ($exe | path exists) {
        error make {msg: $"构建失败: 未生成 ($exe)"}
    }

    let info = (ls $exe | first)
    print $"==> 完成: ($exe)  ($info.size)"
}

def build [] {
    do_build "prod"
}