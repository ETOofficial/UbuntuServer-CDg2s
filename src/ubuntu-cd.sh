#!/bin/bash

# 工具类 ####################################################################################################

format_file_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        size=$(echo "scale=2; $size / 1073741824" | bc)
        size="${size} GB"
    elif [ $size -ge 1048576 ]; then
        size=$(echo "scale=2; $size / 1048576" | bc)
        size="${size} MB"
    elif [ $size -ge 1024 ]; then
        size=$(echo "scale=2; $size / 1024" | bc)
        size="${size} KB"
    else
        size="${size}.00  B"
    fi
    echo "$size"
}

pause() {
    read -rn 1 -p "$1"
}

# 填充一整行输出
# 注意：调用时参数如果是变量，两端不能加颜色代码，否则末尾会有一段距离未填充空格。原因可能是通配符匹配不正确
pad() {
    local line_length=$(printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g' | wc -c) # 计算行长度
    local terminal_width=$(tput cols)                                          # 计算终端宽度

    # 处理多行内容
    # bc 取余运算符无法处理负数
    while ((line_length > terminal_width)); do
        ((line_length -= terminal_width))
    done

    # 计算需要填充的空格数量
    local padding_length=$(echo "$terminal_width - $line_length" | bc)

    local padding=$(printf '%*s' "$padding_length" '') # 生成填充空格
    echo -e "$1$padding"
}

centering() {
    local terminal_width=$(tput cols)
    local line_length=$(printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g' | wc -c)
    # 计算左侧空格数，使用 (cols - len + 1) 处理奇偶问题
    local left=$(echo "( ($terminal_width - $line_length + 1) / 2 )" | bc)
    # 使用printf输出居中文本
    printf "%*s%s\n" "$left" "" "$1"
}

title() {
    echo -e "$RED$black$(pad "$(centering "$1")")$NORMAL$normal"
}

dividing_line() {
    local terminal_width=$(tput cols)                            # 计算终端宽度
    local padding=$(printf '%*s' $terminal_width '' | tr ' ' $1) # 填充
    echo "$padding"
}

# 判断字符串是否包含数组中的任意元素
# 用法：contains_element "字符串" "${数组[@]}"
# 返回匹配的元素，未找到则返回空字符串
contains_element() {
    local str="$1"
    shift # 移除第一个参数（字符串），剩余参数为数组元素
    for element in "$@"; do
        if [[ "$str" == *"$element"* ]]; then
            echo "$element" # 找到匹配
            return
        fi
    done
    echo "" # 未找到匹配
}

not() {
    if [ "$1" = true ]; then
        echo false
    else
        echo true
    fi
}

# 计算动态宽度
get_format_width() {
    local content="$1"
    local desired_width="$2"
    local plain=$(strip_color "$content")
    local plain_length=${#plain}
    local color_length=${#content}
    echo $((desired_width + color_length - plain_length))
}

# 去除颜色代码的函数
strip_color() {
    echo -e "$1" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g'
}

# 裁剪文本并保留颜色代码的函数
# 参数：$1=原始字符串, $2=最大长度（纯文本部分）
# 第二版
# FIXME 问题：含颜色代码的字符串截取后长度小于预期。颜色处理实际上也有问题，不过严重程度低
trim_with_color() {
    local str="$1"
    local max_len="$2"

    # 去除颜色代码后的纯文本及其长度
    local stripped=$(echo -e "$str" | sed -r 's/\x1B\[[0-9;]*[mGK]//g')
    local stripped_len=${#stripped}

    # 如果无需裁剪，直接返回原字符串
    if ((stripped_len <= max_len)); then
        echo -e "$str"
        return
    fi

    local max_allowed=$((max_len - 3)) # 允许的纯文本长度（不含...）
    local parts=()                     # 存储分解后的颜色代码和文本块
    local temp_str="$str"

    # 分解字符串为颜色代码和普通文本块
    while [[ -n "$temp_str" ]]; do
        if [[ "$temp_str" =~ ^($'\x1B'\[[0-9;]*[mGK]) ]]; then
            parts+=("${BASH_REMATCH[1]}")
            temp_str="${temp_str:${#BASH_REMATCH[1]}}"
        elif [[ "$temp_str" =~ ^([^$'\x1B']+) ]]; then
            parts+=("${BASH_REMATCH[1]}")
            temp_str="${temp_str:${#BASH_REMATCH[1]}}"
        else
            break # 处理剩余无效字符
        fi
    done

    local result=""
    local current_len=0
    local truncated=false

    # 构建结果字符串
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^$'\x1B'\[ ]]; then
            # 颜色代码直接添加
            result+="$part"
        else
            # 普通文本处理
            if ((current_len >= max_allowed)); then
                continue
            fi
            local remaining=$((max_allowed - current_len))
            if ((${#part} > remaining)); then
                result+="${part:0:remaining}"
                result+="..."
                current_len=$((max_allowed + 3))
                truncated=true
                break
            else
                result+="$part"
                current_len=$((current_len + ${#part}))
            fi
        fi
    done

    echo -e "$result"
}
# 初版
trim_with_color.disabled() {
    local str="$1"
    local max_len="$2"
    local stripped=$(echo -e "$str" | sed -r 's/\x1B\[[0-9;]*[mGK]//g') # 去除颜色代码
    local stripped_len=${#stripped}

    # 如果纯文本未超长，直接返回原字符串
    if ((stripped_len <= max_len)); then
        echo -e "$str"
        return
    fi

    # 超长时，裁剪纯文本部分（注意保留颜色代码）
    local trimmed=${stripped:0:$((max_len - 3))}"..."

    # 重新添加颜色代码（假设颜色代码在开头）
    # 注意：此处简化处理，假设颜色代码仅在开头。若需复杂场景（如中间有颜色变化），需更复杂的解析。
    local color_code=""
    if [[ "$str" =~ ^(.*\x1B\[[0-9;]*m) ]]; then
        color_code="${BASH_REMATCH[1]}"
    fi

    echo -e "${color_code}${trimmed}$normal" # 添加颜色代码和重置
}

# 处理类 ####################################################################################################

# 定义清理函数
cleanup() {
    eval "$SHOPT_DOTGLOB" # 恢复原始状态
}

# 用法：
#     
search() {
    local OPTIND # 确保选项解析正确，尤其在多次调用函数时

    # 解析选项
    while getopts "rvhptn:d:C:c:M:m:A:a:S:s:N:" opt; do
        case $opt in
        r) srecursive=true ;;  # 启用递归
        n) slevel="$OPTARG" ;; 
        d) sdir="$OPTARG" ;;  # sdir 末尾必须是 /
        v) sverbose=true ;;    # 启用详细模式
        h) shiden=true ;; # 启用搜索隐藏文件
        C)
            sctime_max="$OPTARG"
            sctime=true
            ;;
        c)
            sctime_min="$OPTARG"
            sctime=true
            ;;
        M)
            smtime_max="$OPTARG"
            smtime=true
            ;;
        m)
            smtime_min="$OPTARG"
            smtime=true
            ;;
        A)
            satime_max="$OPTARG"
            satime=true
            ;;
        a)
            satime_min="$OPTARG"
            satime=true
            ;;
        S)
            ssize_max="$OPTARG"
            ssize=true
            ;;
        s)
            ssize_min="$OPTARG"
            ssize=true
            ;;
        p) saccurate=true ;;
        t)
            case "$OPTARG" in
            all | file | directory) stype="$OPTARG" ;;
            *) return 1 ;; # 无效选项时退出
            esac
            ;;
        N) sname="$OPTARG" ;;
        *) return 1 ;; # 无效选项时退出
        esac
    done
    shift $((OPTIND - 1)) # 移除已处理的选项，保留其他参数

    # 确保目录路径以 / 结尾
    [[ "${sdir}" != */ ]] && sdir="${sdir}/"

    # 处理文件匹配逻辑
    if [ "$shiden" = true ]; then
        shopt -s dotglob
    fi
    files=("$sdir"*)
    shopt -u dotglob  # 恢复原设置

    if [ ! -d "$sdir" ]; then
        log_err "Directory not found: $sdir"
        files=()
    elif [ ! -r "$sdir" ]; then
        log_err "Permission denied: $sdir"
        files=()
    else
        files=("$sdir"*)
    fi

    for file in "${files[@]}"; do
        # 处理当前文件的条件判断
        local eligible=true
        # 名称匹配
        if [ "$sname" != "" ] && [ "$saccurate" = false ]; then
            [[ "$(basename "$file")" == *"$sname"* ]] || eligible=false
        else
            [[ "$(basename "$file")" =~ $sname ]] || eligible=false
        fi
        # 类型匹配
        if [ $eligible = true ]; then
            case "$stype" in
            all)
                :
                ;;
            file)
                [ -f "$file" ] || eligible=false
                ;;
            directory)
                [ -d "$file" ] || eligible=false
                ;;
            esac
        fi
        # 时间匹配
        if [ $eligible = true ] && [ "$sctime" = true ]; then
            local ctime=$(stat -c %Z "$file")
            ((ctime >= sctime_min)) || eligible=false
            ((ctime <= sctime_max)) || eligible=false
        fi
        if [ $eligible = true ] && [ "$satime" = true ]; then
            local atime=$(stat -c %X "$file")
            ((atime >= satime_min)) || eligible=false
            ((atime <= satime_max)) || eligible=false
        fi
        if [ $eligible = true ] && [ "$smtime" = true ]; then
            local mtime=$(stat -c %Y "$file")
            ((mtime >= smtime_min)) || eligible=false
            ((mtime <= smtime_max)) || eligible=false
        fi
        # 大小匹配
        if [ $eligible = true ] && [ "$ssize" = true ]; then
            local size=$(stat -c %s "$file")
            ((size >= ssize_min)) || eligible=false
            ((size <= ssize_max)) || eligible=false
        fi

        if [ "$eligible" = true ]; then
            search_result+=("$file")
        fi

        # 处理递归
        if [ -d "$file" ] && [ "$srecursive" = true ]; then
            if ((slevel > 1 || slevel == -1)); then
                ((slevel == -1)) || ((slevel != -1)) && ((slevel--))
                sdir="$file/"
                search $(search_optind)
                ((slevel == -1)) || ((slevel != -1)) && ((slevel++))
            fi
        fi
    done
}

# 整合搜索参数
search_optind() {
    local args=()
    [ $srecursive = true ] && args+=(-r)
    [ $sverbose = true ] && args+=(-v)
    [ $shiden = true ] && args+=(-h)
    [ $saccurate = true ] && args+=(-p)
    ((slevel >= 0)) && args+=(-n "$slevel")
    ((sctime_min != 0)) && args+=(-c "$sctime_min")
    ((sctime_max != 0)) && args+=(-C "$sctime_max")
    ((smtime_min != 0)) && args+=(-m "$smtime_min")
    ((smtime_max != 0)) && args+=(-M "$smtime_max")
    ((satime_min != 0)) && args+=(-a "$satime_min")
    ((satime_max != 0)) && args+=(-A "$satime_max")
    ((ssize_min != 0)) && args+=(-s "$ssize_min")
    ((ssize_max != 0)) && args+=(-S "$ssize_max")
    args+=(-d "$sdir")  # 确保路径用引号包裹，处理空格
    [ "$sname" != "" ] && args+=(-N "$sname")

    echo "${args[@]}"
}

handle_error() {
    local file_name=$1
    local errmsg=$2
    case "$errmsg" in
    *"Permission denied"*)
        echo -e "Permission denied: $file_name\n${yellow}You do not have sufficient privileges, please confirm the current user privileges or switch to a user with sufficient privileges. You can also contact the administrator for help.$normal"
        ;;
    *"No such file or directory"*)
        echo -e "No such file or directory: $file_name\n${yellow}The directory was not found, please check if it exists.$normal"
        ;;
    *"File exists"* | *"mv: overwrite"*)
        echo -e "File exists: $file_name\n${yellow}The file already exists, please choose another name.$normal"
        ;;
    *"Directory not empty"*)
        echo -e "Directory not empty: $file_name\n${yellow}Discover non-empty directories with duplicate names, please delete it first.$normal"
        ;;
    *"are the same file"*)
        echo -e "Same file: $file_name\n${yellow}The file name not changed$normal"
        ;;
    *)
        echo -e "Error: $file_name ($errmsg)"
        ;;
    esac
}

cho_move() {
    while true; do
        # 读取第一个字符（处理转义序列）

        # # 恢复默认终端设置
        # stty sane

        read -rsn1 key

        # 检测键盘
        # 注意：
        #   1.请检查每项处理是否拥有常驻处理项或相应的替代处理
        #       常驻处理项：
        #           confirm_clr
        # FIXME 已知问题：
        #   1. 实际上无法读取回车，按回车读取的结果是空格。空格也被读取成空格。
        #   2. 重命名界面连续按两次回车后有概率出现错误：按上下键都相当于回车。疑似按太快检测有延迟
        if [ "$key" = $'\x1b' ]; then # 用于检测方向键
            # 这里不能 confirm_clr ，否则会无法确认。
            # confirm_clr
            # 读取后续两个字符
            read -rsn2 -t 0.1 rest

            # # 禁用输入缓冲
            # stty -icanon min 1 time 0

            case "$rest" in
            # Up
            '[A' | '^[[A')
                confirm_clr
                ((cho--))
                if ((cho == -1)); then
                    cho=$((${#funcs[@]} - 1))
                fi
                ;;
            # Down
            '[B' | '^[[B')
                confirm_clr
                ((cho++))
                if ((cho == ${#funcs[@]})); then
                    cho=0
                fi
                ;;
            # Right
            '[C' | '^[[C')
                confirm_clr
                if [ "$page" = "main" ]; then
                    if ((cho == 1)); then
                        ((sort_setting++))
                        if ((sort_setting == ${#sort_options[@]})); then
                            sort_setting=0
                        fi
                        refresh=true
                    elif ((cho == ${#funcs[@]} - 1)) && ((file_list_page < file_list_page_max)); then
                        ((file_list_page++))
                        refresh=true
                    fi
                elif [ "$page" = "new" ]; then
                    if ((cho == 0)); then
                        ((new_type_setting++))
                        if ((new_type_setting == ${#new_type_options[@]})); then
                            new_type_setting=0
                        fi
                    fi
                fi
                ;;
            # Left
            '[D' | '^[[D')
                confirm_clr
                if [ "$page" = "main" ]; then
                    if ((cho == 1)); then
                        ((sort_setting--))
                        if ((sort_setting == -1)); then
                            sort_setting=$((${#sort_options[@]} - 1))
                        fi
                        refresh=true
                    elif ((cho == ${#funcs[@]} - 1)) && ((file_list_page > 0)); then
                        ((file_list_page--))
                        refresh=true
                    fi
                elif [ "$page" = "new" ]; then
                    if ((cho == 0)); then
                        ((new_type_setting--))
                        if ((new_type_setting == -1)); then
                            new_type_setting=$((${#new_type_options[@]} - 1))
                        fi
                    fi
                fi
                ;;
            esac
            break
        else
            case "$page" in
            "main")
                # 主页面
                if ((cho == 0)); then # 快速搜索
                    confirm_clr
                    case "$key" in
                    $'\x00')
                        ((cho++))
                        ;;
                    $'\x7f')
                        fast_search_name="${fast_search_name%?}"
                        refresh=true
                        ;;
                    *)
                        fast_search_name+="$key"
                        refresh=true
                        ;;
                    esac
                    break
                else
                    case "$key" in
                    $'\x00')
                        # 回车
                        confirm_clr
                        # 注意：不可删除空处理，因为默认是选择的文件或目录
                        case $cho in

                        # 搜索（已在别处处理）
                        0) ;;
                        # 排序方式
                        1)
                            if [ $sort_r = true ]; then
                                sort_r=false
                            else
                                sort_r=true
                            fi
                            refresh=true
                            ;;

                        # 上级目录所在行数，如果行数有变，需要更改此处
                        2)
                            cd ..
                            refresh=true
                            # log_clr
                            ;;

                        *)
                            if ((cho <= ${#funcs[@]} - 2)); then
                                local file_name="${files[(($cho - 3))]}"
                                local file_type="$(file -b "$file_name")"
                                if [ "$file_type" = "directory" ] || [[ "$file_type" == *"symbolic link"* ]] && [ -d "$file_name" ] ; then
                                    cd "$file_name" 2>"$errfile_path" || {
                                        local errmsg=$(cat "$errfile_path")
                                        log_err "$(handle_error "$file_name" "$errmsg")"
                                    }
                                    cho=0
                                    refresh=true
                                else
                                    log_err "unsupported file type: $file_name | $file_type"
                                fi
                            fi
                            ;;
                        esac
                        break
                        ;;
                    "f")
                        # 刷新
                        confirm_clr
                        if [ "$(refresh_cooling)" = true ]; then # 限制刷新频率
                            log_debug "Refresh cooling"
                            continue
                        fi
                        refresh=true
                        log "Refreshed"
                        break
                        ;;
                    "q")
                        # 退出
                        confirm_clr
                        isexit=true
                        break
                        ;;
                    "n")
                        # 新建
                        confirm_clr
                        new_menu
                        break
                        ;;
                    "~")
                        # 删除（delete）
                        if ((cho <= 2)) && ((cho >= ${#funcs[@]} - 1)); then
                            continue
                        fi

                        # if ((cho != confirm_cho)); then # confirm_clr
                        #     confirm=""
                        # fi

                        local file_name="${files[(($cho - 3))]}"
                        if [ "$confirm" = "delete" ]; then
                            if rm -rf "${file_name}" 2>"$errfile_path"; then
                                log "$yellow$file_name$normal deleted" # rm 成功时记录日志
                            else
                                local errmsg=$(cat "$errfile_path")
                                log_err "$(handle_error "$file_name" "$errmsg")" # rm 失败时记录错误
                            fi
                            confirm=""
                        else
                            log_warn "You are trying to ${red}delete$normal $yellow\"$file_name\"$normal, if you are sure, please type again."
                            # log_debug "confirm=$confirm"
                            confirm="delete"
                        fi
                        refresh=true
                        break
                        ;;
                    "c")
                        # 复制
                        if ((cho <= 2)) && ((cho >= ${#funcs[@]} - 1)); then
                            continue
                        fi

                        confirm_clr
                        local file_name="${files[(($cho - 3))]}"
                        if [ "$(show_prop type $file_name)" = "directory" ]; then
                            copy_name="$(pwd)/$file_name/"
                        else
                            copy_name="$(pwd)/$file_name"
                        fi
                        log "$yellow$file_name$normal copyed"
                        move_name=""
                        break
                        ;;
                    "p")
                        # 粘贴
                        if [ "$copy_name" = "" ]; then
                            if [ "$move_name" = "" ]; then
                                log_err "nothing to paste"
                                break
                            else
                                if [ "$move_name" != "$(pwd)/" ] || [ "$confirm" = "p" ]; then
                                    confirm=""
                                    if mv "$move_name" "$(pwd)/" 2>"$errfile_path"; then
                                        log "$yellow$move_name$normal moved"
                                    else
                                        local errmsg=$(cat "$errfile_path")
                                        log_err "$(handle_error "" "$errmsg")"
                                    fi
                                    move_name=""
                                    refresh=true
                                else
                                    confirm="p"
                                    log_warn "The file already exists, you are trying to ${red}overwrite$normal $yellow\"$move_name\"$normal. If you are sure, please type again."
                                fi
                            fi
                        elif [ "${copy_name: -1}" = "/" ]; then
                            if cp -r "$copy_name" "$(pwd)/" 2>"$errfile_path"; then
                                log "$yellow$copy_name$normal pasted"
                            else
                                local errmsg=$(cat "$errfile_path")
                                log_err "$(handle_error "" "$errmsg")"
                            fi
                            # copy_name=""
                        else
                            if cp "$copy_name" "$(pwd)/" 2>"$errfile_path"; then
                                log "$yellow$copy_name$normal pasted"
                            else
                                local errmsg=$(cat "$errfile_path")
                                log_err "$(handle_error "" "$errmsg")"
                            fi
                            # copy_name=""
                        fi
                        refresh=true
                        break
                        ;;
                    "P")
                        # 粘贴（高级选项）
                        confirm_clr
                        if [ "$copy_name" = "" ] && [ "$move_name" = "" ]; then
                            log_err "nothing to paste"
                            break
                        elif [ "$copy_name" = "" ]; then
                            paste_target_file="$move_name"
                            paste_target_dir="$(pwd)/"
                            paste_menu
                        else
                            paste_target_file="$copy_name"
                            paste_target_dir="$(pwd)/"
                            paste_menu
                        fi
                        refresh=true
                        break
                        ;;
                    "m")
                        # 移动（剪切）
                        if ((cho <= 2)) && ((cho >= ${#funcs[@]} - 1)); then
                            continue
                        fi

                        confirm_clr
                        local file_name="${files[(($cho - 3))]}"
                        move_name="$(pwd)/$file_name"
                        log "$yellow$file_name$normal cuted"
                        copy_name=""
                        break
                        ;;
                    "r")
                        # 重命名
                        if ((cho <= 2)) && ((cho >= ${#funcs[@]} - 1)); then
                            continue
                        fi
                        confirm_clr
                        rename_target_file="${files[(($cho - 3))]}"
                        rename_menu
                        break
                        ;;
                    "s")
                        # 搜索
                        confirm_clr
                        search_menu
                        break
                        ;;
                    *)
                        if [ $debug = true ]; then
                            confirm_clr
                            show_what_has_been_pressed
                            break
                        fi
                        ;;
                    esac
                fi
                ;;
            "new")
                # 新建页面
                if ((cho == 1)); then # 名称输入行
                    confirm_clr
                    if [ "$key" = $'\x7f' ]; then
                        new_name="${new_name%?}"
                        # log_clr
                    elif [ "$key" = "\\" ]; then
                        log_err "unsupported charactor \"\\\""
                    elif [ "$key" = $'\x00' ]; then
                        ((cho++))
                    elif (($(printf '%s' "$new_name" | wc -c) >= 255)); then
                        log_err "name too long"
                    else
                        new_name+="$key"
                        # log_clr
                    fi
                    local unrecommend_chars=("<" ">" "?" "*" "|" "\"" "'" " ")
                    local unrecommend_char="$(contains_element "$new_name" "${unrecommend_chars[@]}")"
                    if [ "$unrecommend_char" != "" ]; then
                        log_warn "unrecommend charactor \"$unrecommend_char\"\nThis character is not recommended because they have special meanings in the shell and may cause command execution errors."
                    fi
                    break

                else
                    case "$key" in
                    $'\x00')
                        # 回车
                        confirm_clr
                        if ((cho == ${#funcs[@]} - 1)); then # 取消
                            isexit=true
                            break
                        elif ((cho == ${#funcs[@]} - 2)); then # 确认
                            if [ "$new_name" = "" ]; then
                                log_err "name cannot be empty"
                            elif [ "${new_type_options[$new_type_setting]}" = "file" ]; then
                                if touch "$new_name" 2>""$errfile_path""; then
                                    log "$yellow$new_name$normal created"
                                    isexit=true
                                else
                                    local errmsg=$(cat "$errfile_path")
                                    log_err "$(handle_error "$new_name" "$errmsg")"
                                    isexit=false
                                fi
                            elif [ "${new_type_options[$new_type_setting]}" = "dirctory" ]; then
                                if mkdir "$new_name" 2>""$errfile_path""; then
                                    log "$yellow$new_name$normal created"
                                    isexit=true
                                else
                                    local errmsg=$(cat "$errfile_path")
                                    log_err "$(handle_error "$new_name" "$errmsg")"
                                    isexit=false
                                fi
                            fi
                            break
                        # elif ((cho == 1)); then # 输入确认
                        #     ((cho++))
                        #     break
                        fi
                        ;;
                    *)
                        confirm_clr
                        show_what_has_been_pressed
                        break
                        ;;
                    esac
                fi
                ;;
            "paste")
                if [ "$copy_name" = "" ]; then
                    local mode="cut"
                else
                    local mode="copy"
                fi

                if [ "$mode" = "cut" ]; then
                    case "$key" in
                    $'\x00')
                        case "$cho" in
                        0)
                            mv_b="$(not "$mv_b")"
                            ;;
                        1)
                            mv_i="$(not "$mv_i")"
                            if [ "$mv_i" = true ]; then
                                mv_f=false
                                mv_n=false
                            fi
                            ;;
                        2)
                            mv_f="$(not "$mv_f")"
                            if [ "$mv_f" = true ]; then
                                mv_i=false
                                mv_n=false
                            fi
                            ;;
                        3)
                            mv_n="$(not "$mv_n")"
                            if [ "$mv_n" = true ]; then
                                mv_i=false
                                mv_f=false
                            fi
                            ;;
                        4)
                            mv_u="$(not "$mv_u")"
                            ;;
                        5)
                            mv_v="$(not "$mv_v")"
                            ;;
                        6)
                            mv_T="$(not "$mv_T")"
                            ;;
                        *)
                            local args=()
                            [[ "$mv_b" == true ]] && args+=("-b")
                            [[ "$mv_i" == true ]] && args+=("-i")
                            [[ "$mv_f" == true ]] && args+=("-f")
                            [[ "$mv_n" == true ]] && args+=("-n")
                            [[ "$mv_u" == true ]] && args+=("-u")
                            [[ "$mv_v" == true ]] && args+=("-v")
                            [[ "$mv_T" == true ]] && args+=("-T")
                            if ((cho == ${#funcs[@]} - 2)); then
                                isexit=true
                                clear
                                echo "> mv ${args[*]} $paste_target_file $paste_target_dir"
                                echo "Output:"
                                mv "${args[@]}" "$paste_target_file" "$paste_target_dir" 2>&1 | tee ""$errfile_path""
                                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                                    errmsg=$(cat "$errfile_path")
                                    log_err "$(handle_error "$paste_target_file" "$errmsg")"
                                    isexit=false
                                fi
                                echo ""
                                dividing_line "-"
                                pause "Press any key to continue..."
                            else
                                isexit=true
                            fi
                            ;;
                        esac
                        break
                        ;;
                    esac
                elif [ "$mode" = "copy" ]; then
                    case "$key" in
                    $'\x00')
                        case "$cho" in
                        0)
                            cp_b="$(not "$cp_b")"
                            if [ "$cp_b" = true ]; then
                                cp_n=false
                            fi
                            ;;
                        1)
                            cp_f="$(not "$cp_f")"
                            if [ "$cp_f" = true ]; then
                                cp_i=false
                                cp_n=false
                            fi
                            ;;
                        2)
                            cp_i="$(not "$cp_i")"
                            if [ "$cp_i" = true ]; then
                                cp_f=false
                                cp_n=false
                            fi
                            ;;
                        3)
                            cp_H="$(not "$cp_H")"
                            if [ "$cp_H" = true ]; then
                                cp_P=false
                                cp_L=false
                            fi
                            ;;
                        4)
                            cp_l="$(not "$cp_l")"
                            if [ "$cp_l" = true ]; then
                                cp_s=false
                            fi
                            ;;
                        5)
                            cp_L="$(not "$cp_L")"
                            if [ "$cp_L" = true ]; then
                                cp_P=false
                                cp_H=false
                            fi
                            ;;
                        6)
                            cp_n="$(not "$cp_n")"
                            if [ "$cp_n" = true ]; then
                                cp_b=false
                                cp_i=false
                                cp_f=false
                            fi
                            ;;
                        7)
                            cp_P="$(not "$cp_P")"
                            if [ "$cp_P" = true ]; then
                                cp_L=false
                                cp_H=false
                            fi
                            ;;
                        8)
                            cp_r="$(not "$cp_r")"
                            ;;
                        9)
                            cp_s="$(not "$cp_s")"
                            if [ "$cp_s" = true ]; then
                                cp_l=false
                            fi
                            ;;
                        10)
                            cp_T="$(not "$cp_T")"
                            ;;
                        11)
                            cp_u="$(not "$cp_u")"
                            ;;
                        12)
                            cp_v="$(not "$cp_v")"
                            ;;
                        13)
                            cp_x="$(not "$cp_x")"
                            ;;
                        *)
                            local args=()
                            [[ "$cp_b" == true ]] && args+=("-b")
                            [[ "$cp_f" == true ]] && args+=("-f")
                            [[ "$cp_i" == true ]] && args+=("-i")
                            [[ "$cp_H" == true ]] && args+=("-H")
                            [[ "$cp_l" == true ]] && args+=("-l")
                            [[ "$cp_L" == true ]] && args+=("-L")
                            [[ "$cp_n" == true ]] && args+=("-n")
                            [[ "$cp_P" == true ]] && args+=("-P")
                            [[ "$cp_r" == true ]] && args+=("-r")
                            [[ "$cp_s" == true ]] && args+=("-s")
                            [[ "$cp_T" == true ]] && args+=("-T")
                            [[ "$cp_u" == true ]] && args+=("-u")
                            [[ "$cp_v" == true ]] && args+=("-v")
                            [[ "$cp_x" == true ]] && args+=("-x")
                            if ((cho == ${#funcs[@]} - 2)); then
                                isexit=true
                                clear
                                echo "> cp ${args[*]} $paste_target_file $paste_target_dir"
                                echo "Output:"
                                cp "${args[@]}" "$paste_target_file" "$paste_target_dir" 2>&1 | tee ""$errfile_path""
                                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                                    errmsg=$(cat "$errfile_path")
                                    log_err "$(handle_error "$paste_target_file" "$errmsg")"
                                    isexit=false
                                fi
                                echo ""
                                dividing_line "-"
                                pause "Press any key to continue..."
                            else
                                isexit=true
                            fi
                            ;;
                        esac
                        break
                        ;;
                    esac
                fi
                ;;
            "rename")
                if ((cho == 0)); then # 名称输入行
                    confirm_clr
                    if [ "$key" = $'\x7f' ]; then
                        rename_name="${rename_name%?}"
                    elif [ "$key" = "\\" ]; then
                        log_err "unsupported charactor \"\\\""
                    elif [ "$key" = $'\x00' ]; then
                        ((cho++))
                    elif (($(printf '%s' "$rename_name" | wc -c) >= 255)); then
                        log_err "name too long"
                    else
                        rename_name+="$key"
                    fi
                    local unrecommend_chars=("<" ">" "?" "*" "|" "\"" "'" " ")
                    local unrecommend_char="$(contains_element "$rename_name" "${unrecommend_chars[@]}")"
                    if [ "$unrecommend_char" != "" ]; then
                        log_warn "unrecommend charactor \"$unrecommend_char\"\nThis character is not recommended because they have special meanings in the shell and may cause command execution errors."
                    fi
                    break
                else
                    case "$key" in
                    $'\x00')
                        # 回车
                        confirm_clr
                        if ((cho == ${#funcs[@]} - 1)); then # 取消
                            isexit=true
                            break
                        elif ((cho == ${#funcs[@]} - 2)); then # 确认
                            if [ "$rename_name" = "" ]; then
                                log_err "name cannot be empty"
                            else
                                # 覆盖不会报错，目前只能让用户交互
                                if mv -i "$rename_target_file" "$rename_name" 2>""$errfile_path""; then
                                    log "$yellow$rename_target_file$normal renamed to $yellow$rename_name$normal"
                                    isexit=true
                                else
                                    local errmsg=$(cat "$errfile_path")
                                    log_err "$(handle_error "$rename_name" "$errmsg")"
                                    isexit=false
                                fi
                            fi
                            break
                        elif ((cho == 0)); then # 输入确认
                            ((cho++))
                            break
                        fi
                        ;;
                    *)
                        confirm_clr
                        show_what_has_been_pressed
                        break
                        ;;
                    esac
                fi
                ;;
            esac
        fi
    done
}

# 返回值：如果刷新时间已过设定时长，则返回 false，否则返回 true
refresh_cooling() {
    local time=$(date +%s.%N)
    # 返回 true 表示需要冷却（距离上次刷新不足0.1秒）
    if awk -v t="$time" -v rt="$refresh_time" 'BEGIN { exit (t - rt > 0.1) }'; then
        echo true
    else
        echo false
    fi
}

# 菜单类 ####################################################################################################

# 主菜单
# TODO 选择处于文件列表时，左右键切换右边的属性显示
__main_menu__() {
    if ((cho == ${#funcs[@]} - 1)); then
        local refresh_cho=true
    else
        local refresh_cho=false
    fi
    # 显示页眉
    title "Ubuntu-CD Explorer"
    title "[N]ew${TAB}[Del]ete${TAB}[M]ove(Cut)${TAB}[C]opy${TAB}[P]aste${TAB}[R]ename${TAB}[S]earch${TAB}pr[o]perties${TAB}re[F]resh${TAB}[Q]uit"
    echo -e "Current directory: $yellow$(pwd)$normal"

    # 处理文件列表
    # 仅需要刷新时处理，减少卡顿
    # FIXME 快速搜索内容变化时仍然会卡顿，将搜索栏优先刷新
    # TODO 快速搜索功能实现
    if [ $refresh = true ]; then
        refresh_time=$(date +%s.%N)
        echo -e "${RED}${black}loading...$NORMAL$normal"
        echo -en "\033[1A" # 将光标向上移动 1 行
        log_debug "refreshed"
        shopt -s nullglob # 设置nullglob选项，使没有匹配时返回空数组
        # TODO 增加隐藏功能开关
        shopt -s dotglob  # 启用包含隐藏文件的glob模式
        files=(*)         # 将当前目录下的所有文件和目录存入数组
        shopt -u nullglob # 取消nullglob选项，避免影响后续命令
        shopt -u dotglob  # 恢复默认的glob模式

        # 排序
        local sort_start_time=$(date +%s.%N)
        local sort_mode="${sort_options[$sort_setting]}"
        # TODO 其余排序方式
        if [ "$sort_mode" = "name" ]; then
            if [ $sort_r = true ]; then
                files=($(printf "%s\n" "${files[@]}" | sort -r))
            else
                files=($(printf "%s\n" "${files[@]}" | sort))
            fi
        elif [ "$sort_mode" = "size" ]; then
            local sorted_files=()
            while IFS= read -r line; do # 确保安全读取文件名
                sorted_files+=("$line")
            done < <(
                # 遍历文件，输出格式：大小 文件名
                for file in "${files[@]}"; do
                    if [[ -e "$file" ]]; then
                        size=$(stat -c "%s" "$file" | awk '{print $1}') # 获取大小
                        printf "%s %s\n" "$size" "$file"
                    fi
                done |
                    if [ $sort_r = true ]; then
                        sort -nr
                    else
                        sort -n
                    fi | cut -d ' ' -f2- # 按数值排序后提取文件名
            )
            files=("${sorted_files[@]}")
        elif [ "$sort_mode" = "modified date" ]; then
            local sorted_files=()
            while IFS= read -r line; do # 确保安全读取文件名
                sorted_files+=("$line")
            done < <(
                # 遍历文件，输出格式：大小 文件名
                for file in "${files[@]}"; do
                    if [[ -e "$file" ]]; then
                        mtime=$(stat -c "%Y" "$file") # 获取修改时间戳
                        printf "%s %s\n" "$mtime" "$file"
                    fi
                done |
                    if [ $sort_r = true ]; then
                        sort -nr
                    else
                        sort -n
                    fi | cut -d ' ' -f2- # 按数值排序后提取文件名
            )
            files=("${sorted_files[@]}")
        fi
        log_debug "Sorting time consuming: $(echo "$(date +%s.%N) - $sort_start_time" | bc | awk '{printf "%.2f", $1}')s"

        files_form=() # 用于存储每行应该显示的内容

        file_list_page_max=$(((${#files[@]} + file_list_line - 1) / file_list_line - 1))
        if ((file_list_page > file_list_page_max)); then
            file_list_page=$file_list_page_max
        fi
        local i=0
        local j=0
        for file in "${files[@]}"; do
            if ((i < file_list_page * file_list_line)); then # 跳过前几页
                ((i++))
                continue
            elif ((i >= (file_list_page + 1) * file_list_line)); then # 超过当前页时终止
                break
            fi

            # 处理当前页文件（文件索引在 [page*max, (page+1)*max) 区间）
            local file_type=$(show_prop type "$file")
            if [ "$file_type" = "directory" ]; then
                local file_name=$blue$file"/"$normal
                local file_size=$blue"/"$normal
                file_type=$blue$file_type$normal
            elif [ "$file_type" = "symbolic link" ]; then
                local link_target=$(readlink $file)
                if [ -d "$link_target" ]; then
                    local file_name=$blue$file"@/"$normal
                    local file_size=$blue"@/"$normal
                else
                    local file_name=$blue$file"@"$normal
                    local file_size=$blue"@"$normal
                fi
            else
                local file_name=$file
                local file_size=$(show_prop size "$file")
            fi
            local mtime="$(show_prop mt "$file")"

            # 对每个字段裁剪并格式化
            file_name=$(trim_with_color "$file_name" 29) # 29字符（留1位给填充）
            mtime=$(trim_with_color "$mtime" 29)
            file_type=$(trim_with_color "$file_type" 29)
            file_size=$(trim_with_color "$file_size" 14) # %+15.29s → 14字符（留1位给符号）

            # 对每个变量计算动态宽度
            local file_name_width=$(get_format_width "$file_name" 30)
            local smtime_width=$(get_format_width "$mtime" 30)
            local file_type_width=$(get_format_width "$file_type" 30)
            local file_size_width=$(get_format_width "$file_size" 10)

            # files_form[j]=$(printf "%-30.29s %-30.29s %-30.29s %+15.29s" "$file_name" "$mtime" "$file_type" "$file_size")

            # 使用动态宽度格式化输出
            files_form[j]=$(printf "%-*s %-*s %-*s %+*s" \
                "$file_name_width" "$file_name" \
                "$smtime_width" "$mtime" \
                "$file_type_width" "$file_type" \
                "$file_size_width" "$file_size")

            ((j++))
            ((i++))
        done
        # 可以被选中的内容
        funcs=("Fast Search: $fast_search_name" "$(show_sort_by)" ".." "${files_form[@]}" "$(centering "< Page $((file_list_page + 1)) / $((file_list_page_max + 1)) >")")

        refresh=false
    fi

    if [ "$refresh_cho" = true ]; then
        cho=$((${#funcs[@]} - 1))
    fi

    if ((cho > ${#funcs[@]} - 1)); then
        cho=$((${#funcs[@]} - 1))
    fi

    # 显示页面
    local i=0
    for func in "${funcs[@]}"; do
        if ((cho == i)); then
            echo -e "$GREEN$(pad "$func")"
        else
            echo -e "$NORMAL$func"
        fi
        # 显示表头
        if ((i == 1)); then
            echo -ne "$NORMAL"
            dividing_line "-"
            printf "%-30s %-30s %-30s %+10s" "Name" "Modified Date" "Type" "Size"
            echo ""
        fi
        ((i++))
    done

    # 显示页尾
    echo -e "$NORMAL"
    echo -e "$log_info"
}

# 新建菜单
# TODO 链接文件
__new_menu__() {
    # 显示页眉
    title "New"
    echo -e "Current directory: $yellow$(pwd)$normal"

    # 显示页面
    funcs=("$(show_new_type)" "Name: $new_name" "Confirm" "Cancel")

    local i=0
    for func in "${funcs[@]}"; do
        if ((cho == i)); then
            echo -e "$GREEN$(pad "$func")"
        else
            echo -e "$NORMAL$func"
        fi
        if ((i == ${#funcs[@]} - 3)); then
            echo -en "$NORMAL"
            dividing_line "-"
        fi
        ((i++))
    done

    # 显示页尾
    echo -e "$NORMAL"
    echo -e "$log_info"
}

# 粘贴菜单
__paste_menu__() {
    # 显示页眉
    title "Paste"
    echo -e "Target file: $yellow$paste_target_file$normal"
    echo -e "Target directory: $yellow$paste_target_dir$normal"
    if [ "$copy_name" = "" ]; then
        echo -e "Mode: ${yellow}Cut$normal"
        local mode="cut"
    else
        echo -e "Mode: ${yellow}Copy$normal"
        local mode="copy"
    fi

    # 处理要显示的内容
    if [ "$mode" = "cut" ]; then
        funcs=(
            "$(printf "%s %-15s %s" "$(show_bool "$mv_b")" "backup" "make a backup of each existing destination file")"
            "$(printf "%s %-15s %s" "$(show_bool "$mv_i")" "interactive" "prompt before overwrite")"
            "$(printf "%s %-15s %s" "$(show_bool "$mv_f")" "force" "do not prompt before overwriting")"
            "$(printf "%s %-15s %s" "$(show_bool "$mv_n")" "no-clobber" "do not overwrite an existing file")"
            "$(printf "%s %-15s %s" "$(show_bool "$mv_u")" "updated" "updated files")"
            "$(printf "%s %-15s %s" "$(show_bool "$mv_v")" "verbose" "explain what is being done")"
            "$(printf "%s %-15s %s" "$(show_bool "$mv_T")" "DEST as normal" "treat DEST as a normal file")"
            "Confirm"
            "Cancel"
        )
    elif [ "$mode" = "copy" ]; then
        funcs=(
            "$(printf "%s %-15s %s" "$(show_bool "$cp_b")" "backup" "make a backup of each existing destination file")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_f")" "force" "if an existing destination file cannot be opened, remove it and try again")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_i")" "interactive" "prompt before overwrite")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_H")" "follow CL" "follow command-line symbolic links in SOURCE")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_l")" "link" "hard link files instead of copying")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_L")" "dereference" "always follow symbolic links in SOURCE")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_n")" "no-clobber " "do not overwrite an existing file and do not fail")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_P")" "no-dereference" "never follow symbolic links in SOURCE")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_r")" "recursive" "copy directories recursively")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_s")" "symbolic-link" "make symbolic links instead of copying")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_T")" "no-tardirectory" "treat DEST as a normal file")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_u")" "updated" "updated files")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_v")" "verbose" "explain what is being done")"
            "$(printf "%s %-15s %s" "$(show_bool "$cp_x")" "one-file-system" "stay on this file system")"
            "Confirm"
            "Cancel"
        )
    fi

    # 显示页面
    local i=0
    for func in "${funcs[@]}"; do
        if ((cho == i)); then
            echo -e "$GREEN$(pad "$func")"
        else
            echo -e "$NORMAL$func"
        fi
        # if ((i == ${#funcs[@]} - 3)); then
        #     echo -en "$NORMAL"
        #     dividing_line "-"
        # fi
        ((i++))
    done

    # 显示页尾
    echo -e "$NORMAL"
    echo -e "$log_info"
}

# 重命名菜单
__rename_menu__() {
    # 显示页眉
    title "Rename"
    echo -e "Target file: $yellow$rename_target_file$normal"

    funcs=("Name: $rename_name" "Confirm" "Cancel")

    # 显示页面
    local i=0
    for func in "${funcs[@]}"; do
        if ((cho == i)); then
            echo -e "$GREEN$(pad "$func")"
        else
            echo -e "$NORMAL$func"
        fi
        ((i++))
    done

    # 显示页尾
    echo -e "$NORMAL"
    echo -e "$log_info"
}

# 搜索菜单
__search_menu__() {
    # 显示页眉

    # 显示页面
    # 测试
    sname='*e*'
    saccurate=true
    sdir="$(pwd)"
    shiden=true
    # sctime=true
    # sctime_min=1000000000
    # sctime_max=1999999999
    slevel=3
    srecursive=true
    echo "$(search_optind)"
    echo ""
    search $(search_optind)
    echo "${search_result[*]}"

    # 显示页尾
    echo -e "$NORMAL"
    echo -e "$log_info"
}

# 之后的 menu 函数用于直接调用
main_menu() {
    # log_clr
    while [ "$isexit" = false ]; do
        clear
        __main_menu__
        cho_move
    done
}

new_menu() {
    funcs=()
    confirm_clr
    page="new"
    cho=0
    # log_clr

    while [ "$isexit" = false ]; do
        clear
        __new_menu__
        cho_move
    done

    isexit=false
    page="main"
    cho=0
    refresh=true
}

paste_menu() {
    # paste_target_file=$1
    # paste_target_dir=$2

    funcs=()
    confirm_clr
    page="paste"
    cho=0
    # log_clr

    while [ "$isexit" = false ]; do
        clear
        __paste_menu__
        cho_move
    done

    isexit=false
    page="main"
    cho=0
    refresh=true
}

rename_menu() {
    funcs=()
    confirm_clr
    page="rename"
    cho=0

    while [ "$isexit" = false ]; do
        clear
        __rename_menu__
        cho_move
    done

    isexit=false
    page="main"
    cho=0
    refresh=true
}

search_menu() { 
    funcs=()
    confirm_clr
    page="search"
    cho=0

    while [ "$isexit" = false ]; do
        clear
        __search_menu__
        cho_move
    done

    isexit=false
    page="main"
    cho=0
    refresh=true
}

# 其余显示函数
show_sort_by() {
    echo -n "Sort by(reverse:$sort_r):$TAB"
    local i=0
    for option in "${sort_options[@]}"; do
        if ((sort_setting == i)); then
            echo -ne "< $yellow$option$normal >$TAB"
        else
            echo -ne "$option$TAB"
        fi
        ((i++))
    done
}

show_new_type() {
    echo -n "Type:$TAB"
    local i=0
    for type in "${new_type_options[@]}"; do
        if ((new_type_setting == i)); then
            echo -ne "< $yellow$type$normal >$TAB"
        else
            echo -ne "$type$TAB"
        fi
        ((i++))
    done
}

show_bool() {
    if [ "$1" = true ]; then
        echo -ne "[x]"
    else
        echo -ne "[ ]"
    fi
}

# 显示文件属性
show_prop() {
    if [ "$1" = "mt" ] || [ "$1" = "mtime" ]; then # 修改时间
        stat -c "%y" "$2" | cut -d '.' -f 1
    elif [ "$1" = "ct" ] || [ "$1" = "ctime" ]; then # 变化时间
        stat -c "%z" "$2" | cut -d '.' -f 1
    elif [ "$1" = "at" ] || [ "$1" = "atime" ]; then # 访问时间
        stat -c "%x" "$2" | cut -d '.' -f 1
    elif [ "$1" = "size" ]; then
        format_file_size "$(stat -c "%s" "$file")"
    elif [ "$1" = "type" ]; then
        stat -c "%F" "$2"
    fi
}

# 日志类 ####################################################################################################

log_time() {
    date "+[%Y-%m-%d %H:%M:%S]"
}
log() {
    echo "$(log_time) $1" >>"$log_path"
    log_show
}
log_warn() {
    echo "$(log_time) ${YELLOW}${black}[WARNING]$NORMAL $1" >>"$log_path"
    log_show
}
log_err() {
    echo "$(log_time) ${RED}[ERROR]$NORMAL $1" >>"$log_path"
    log_show
}
log_debug() {
    if [ $debug = true ]; then
        echo "$(log_time) ${BLUE}[DEBUG]$NORMAL $1" >>"$log_path"
        log_show
    fi
}
log_clr() {
    echo "Start Logging >>>" >"$log_path"
    log_show
}
log_show() {
    log_info="$(dividing_line "-")\n$(tail -n $log_info_line "$log_path")"
}

confirm_clr() {
    confirm=""
}

show_what_has_been_pressed() {
    log_debug "Key pressed: '$key' (ASCII: $(printf %d "'$key")))"
}

# 初始化 ####################################################################################################

# 颜色转义字符，小写为字体颜色，大写为背景颜色
NORMAL='\033[0m'
normal='\033[37m'
GREEN='\033[42m'
YELLOW='\033[43m'
yellow='\033[33m'
black='\033[30m'
RED='\033[41m'
red='\033[31m'
BLUE='\033[44m'
blue='\033[34m'
TAB="    "

sort_options=("name" "size" "modified date") # 排序选项
new_type_options=("file" "dirctory")         # 新建类型

funcs=()             # 存储可选行
isexit=false         # 是否退出
refresh=true         # 是否刷新
debug=false          # 调试模式
cho=0                # 当前选择行
page="main"          # 当前页面
sort_setting=0       # 排序选项
sort_r=false         # 是否倒序排序
new_type_setting=0   # 新建类型选项
refresh_time=0       # 刷新时间
log_info_line=5      # 日志信息行数
file_list_line=20    # 文件列表行数
file_list_page=0     # 文件列表页数
file_list_page_max=0 # 文件列表页数最大值
search_result=()     # 搜索结果

# 搜索选项
srecursive=false
sverbose=false
shiden=false # 是否搜索隐藏文件
sctime=false
smtime=false
satime=false
ssize=false
stype=all
sname=""
saccurate=false # 是否精确匹配，参数为 -p
sdir="*"
slevel=0 # 递归层数
sctime_min=0
sctime_max=0
smtime_min=0
smtime_max=0
satime_min=0
satime_max=0
ssize_min=0
ssize_max=0

errfile_path="/tmp/ubuntu-cd.err" # 错误日志路径
log_path="/tmp/ubuntu-cd.log"     # 日志路径
loading_percent_file="/tmp/ubuntu-cd-loading-percent.tmp"

# 由于对命令参数知识较为匮乏，目前只包含部分参数
mv_b=false
mv_u=false
mv_n=false
mv_i=false
mv_f=false
mv_T=false
mv_v=false

cp_b=false
cp_f=false
cp_i=false
cp_H=false
cp_l=false
cp_L=false
cp_n=false
cp_P=false
cp_r=false
cp_s=false
cp_T=false
cp_u=false
cp_v=false
cp_x=false

log_clr

for arg in "$@"; do
    case $arg in
    --debug)
        debug=true
        log_debug "Debug mode is on"
        ;;
    --pwd=*)
        start_dir="${arg#*=}" # 提取等号后的路径部分
        if [ ! -d "$start_dir" ]; then
            echo "Invalid directory: $start_dir"
            exit 1
        fi
        cd "$start_dir" || exit 1
        ;;
    --help)
        echo ""
        echo "Usage:"
        echo "    ubuntu-cd [options]"
        echo ""
        echo "Options:"
        echo "    --debug         Enable debug mode"
        echo "    --pwd=<path>    Start in the specified directory"
        echo "    --help          Show this help message"
        echo ""
        exit 0
        ;;
    *)
        echo "ubuntu-cd: Unknown argument: $arg"
        echo "Try 'ubuntu-cd --help' for more information."
        exit 1
        ;;
    esac
done

# 保存原始状态
SHOPT_DOTGLOB=$(shopt -p dotglob)
trap cleanup EXIT

main_menu
