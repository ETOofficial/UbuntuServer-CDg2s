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

# 显示文件属性
show_prop() {
    if [ "$1" = "mt" ] || [ "$1" = "mtime" ]; then
        stat -c "%y" "$2" | cut -d '.' -f 1
    elif [ "$1" = "ct" ] || [ "$1" = "ctime" ]; then
        stat -c "%z" "$2" | cut -d '.' -f 1
    elif [ "$1" = "at" ] || [ "$1" = "atime" ]; then
        stat -c "%x" "$2" | cut -d '.' -f 1
    elif [ "$1" = "size" ]; then
        format_file_size "$(stat -c "%s" "$file")"
    elif [ "$1" = "type" ]; then
        stat -c "%F" "$2"
    fi
}

bool2str() {
    if $1; then
        echo -en "$2"
    else
        echo -en "$3"
    fi
}

pause() {
    read -rn 1 -p "$1"
}

# 填充一整行输出
# 注意：调用时参数如果是变量，两端不能加颜色代码，否则末尾会有一段距离未填充空格
pad() {
    local line_length=$(printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g' | wc -c) # 计算行长度
    local terminal_width=$(tput cols)                                          # 计算终端宽度

    # 处理多行内容
    while ((line_length > terminal_width)); do
        ((line_length-=terminal_width))
    done

    # 计算需要填充的空格数量
    local padding_length=$(echo "$terminal_width - $line_length" | bc)

    local padding=$(printf '%*s' $padding_length '') # 生成填充空格
    echo -e "$1$padding"
}

centering(){
    local terminal_width=$(tput cols)
    local line_length=$(printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g' | wc -c)
    # 计算左侧空格数，使用 (cols - len + 1) 处理奇偶问题
    local left=$(echo "( ($terminal_width - $line_length + 1) / 2 )" | bc)
    # 使用printf输出居中文本
    printf "%*s%s\n" "$left" "" "$1"
}

title(){
    echo -e "$RED$black$(pad "$(centering "$1")")$NORMAL$normal"
}

dividing_line() {
    local terminal_width=$(tput cols)                             # 计算终端宽度
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

reverse_bool() {
    if $1; then
        echo false
    else
        echo true
    fi
}

# 处理类 ####################################################################################################

cho_move() {
    while true; do
        # 读取第一个字符（处理转义序列）
        read -rsn1 key
        # 检测键盘
        # 注意：
        #   1.请检查每项处理是否拥有常驻处理项或相应的替代处理
        #       常驻处理项：
        #           confirm_clr
        # FIXME 已知问题：实际上无法读取回车，按回车读取的结果是空格
        if [ "$key" = $'\x1b' ]; then # 用于检测方向键
            # 这里不能 confirm_clr ，否则会无法确认，原因未知。
            # confirm_clr
            # 读取后续两个字符
            read -rsn2 -t 0.1 rest
            case "$rest" in
            # Up
            '[A')
                confirm_clr
                ((cho--))
                if ((cho == -1)); then
                    cho=$((${#funcs[@]} - 1))
                fi
                ;;
            # Down
            '[B')
                confirm_clr
                ((cho++))
                if ((cho == ${#funcs[@]})); then
                    cho=0
                fi
                ;;
            # Right
            '[C')
                confirm_clr
                if [ "$page" = "main" ]; then
                    if ((cho == 1)); then
                        ((sort_setting++))
                        if ((sort_setting == ${#sort_options[@]})); then
                            sort_setting=0
                        fi
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
            '[D')
                confirm_clr
                if [ "$page" = "main" ]; then
                    if ((cho == 1)); then
                        ((sort_setting--))
                        if ((sort_setting == -1)); then
                            sort_setting=$((${#sort_options[@]} - 1))
                        fi
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
                        # TODO 添加换页功能以应对过多的文件
                        # 注意：不可删除空处理，因为默认是选择的文件或目录
                        case $cho in

                        # 搜索（已在别处处理）
                        0) ;;
                        # 排序方式
                        1)
                            if $sort_r; then
                                sort_r=false
                            else
                                sort_r=true
                            fi
                            refresh=true
                            ;;

                        # 上级目录所在行数，如果行数有变，需要更改此处
                        2)
                            cd ..
                            cho=0
                            refresh=true
                            log_clr
                            ;;

                        *)
                            log_clr
                            local file_name="${files[(($cho - 3))]}"
                            local file_type="$(file -b "$file_name")"
                            if [ "$file_type" = "directory" ]; then
                                cd "$file_name" 2>/tmp/ubuntu-cd || {
                                    local error_message=$(cat /tmp/ubuntu-cd)
                                    log_err "$(handle_error "$file_name" "$error_message")"
                                }
                                cho=0
                                refresh=true
                            else
                                log_err "unsupported file type: $file_name | $file_type"
                            fi
                            ;;
                        esac
                        break
                        ;;
                    "f")
                        # 刷新
                        confirm_clr
                        if $(refresh_cooling); then # 限制刷新频率
                            break
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
                        if ((cho == 0)) && ((cho == 1)) && ((cho == 2)); then
                            continue
                        fi

                        # if ((cho != confirm_cho)); then # confirm_clr
                        #     confirm=""
                        # fi

                        local file_name="${files[(($cho - 3))]}"
                        if [ "$confirm" = "delete" ]; then
                            log "$yellow$file_name$normal deleted"
                            rm -rf "${file_name}" 2>/tmp/ubuntu-cd || {
                                local error_message=$(cat /tmp/ubuntu-cd)
                                log_err "$(handle_error "$file_name" "$error_message")"
                            }
                            confirm=""
                        else
                            confirm_cho="$cho"
                            log_warn "You are trying to ${red}delete$normal $yellow\"$file_name\"$normal, if you are sure, please type again."
                            # if [ "$debug" = true ]; then
                            #     log_debug "confirm=$confirm"
                            # fi
                            confirm="delete"
                        fi
                        refresh=true
                        break
                        ;;
                    "c")
                        # 复制
                        if ((cho == 0)) && ((cho == 1)) && ((cho == 2)); then
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

                        # if ((cho != confirm_cho)); then # confirm_clr
                        #     confirm=""
                        # fi

                        reload=true

                        if [ "$copy_name" = "" ]; then
                            if [ "$move_name" = "" ]; then
                                log_err "nothing to paste"
                                break
                            else
                                if [ "$move_name" != "$(pwd)/" ] || [ "$confirm" = "p" ]; then
                                    confirm=""
                                    log "$yellow$move_name$normal moved"
                                    mv "$move_name" "$(pwd)/" 2>/tmp/ubuntu-cd || {
                                        local error_message=$(cat /tmp/ubuntu-cd)
                                        log_err "$(handle_error "" "$error_message")"
                                    }
                                    move_name=""
                                    refresh=true
                                else
                                    confirm="p"
                                    log_warn "The file already exists, you are trying to ${red}overwrite$normal $yellow\"$move_name\"$normal. If you are sure, please type again."
                                fi
                            fi
                        elif [ "${copy_name: -1}" = "/" ]; then
                            log "$yellow$copy_name$normal pasted"
                            cp -r "$copy_name" "$(pwd)/" 2>/tmp/ubuntu-cd || {
                                local error_message=$(cat /tmp/ubuntu-cd)
                                log_err "$(handle_error "" "$error_message")"
                            }
                            # copy_name=""
                        else
                            log "$yellow$copy_name$normal pasted"
                            cp "$copy_name" "$(pwd)/" 2>/tmp/ubuntu-cd || {
                                local error_message=$(cat /tmp/ubuntu-cd)
                                log_err "$(handle_error "" "$error_message")"
                            }
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
                            paste_menu "$move_name" "$(pwd)/"
                        else
                            paste_menu "$copy_name" "$(pwd)/"
                        fi
                        refresh=true
                        break
                        ;;
                    "m")
                        # 移动（剪切）
                        if ((cho == 0)) && ((cho == 1)) && ((cho == 2)); then
                            continue
                        fi

                        confirm_clr
                        local file_name="${files[(($cho - 3))]}"
                        move_name="$(pwd)/$file_name"
                        log "$yellow$file_name$normal cuted"
                        copy_name=""
                        break
                        ;;
                    *)
                        if $debug; then
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
                        log_clr
                    elif [ "$key" = "\\" ]; then
                        log_err "unsupported charactor \"\\\""
                    elif (($(printf '%s' "$new_name" | wc -c) >= 255)); then
                        log_err "name too long"
                    else
                        new_name+="$key"
                        log_clr
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
                                log "$yellow$new_name$normal created"
                                isexit=true
                                touch "$new_name" 2>"/tmp/ubuntu-cd" || {
                                    local error_message=$(cat /tmp/ubuntu-cd)
                                    log_err "$(handle_error "$new_name" "$error_message")"
                                    isexit=false
                                }
                            elif [ "${new_type_options[$new_type_setting]}" = "dirctory" ]; then
                                log "$yellow$new_name$normal created"
                                isexit=true
                                mkdir "$new_name" 2>"/tmp/ubuntu-cd" || {
                                    local error_message=$(cat /tmp/ubuntu-cd)
                                    log_err "$(handle_error "$new_name" "$error_message")"
                                    isexit=false
                                }
                            fi
                            break
                        elif ((cho == 1)); then # 输入确认
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
            "paste")
                if [ "$copy_name" = "" ]; then
                    case "$key" in
                    $'\x00')
                        case "$cho" in
                        0)
                            mv_b="$(reverse_bool "$mv_b")"
                            ;;
                        1)
                            mv_i="$(reverse_bool "$mv_i")"
                            ;;
                        2)
                            mv_f="$(reverse_bool "$mv_f")"
                            ;;
                        3)
                            mv_n="$(reverse_bool "$mv_n")"
                            ;;
                        4)
                            mv_u="$(reverse_bool "$mv_u")"
                            ;;
                        5)
                            clear
                            echo "Output:"
                            mv "-$(bool2str "$mv_b" "b" "")$(bool2str "$mv_i" "i" "")$(bool2str "$mv_f" "f" "")$(bool2str "$mv_n" "n" "")$(bool2str "$mv_u" "u" "")" "$target_file" "$target_dir"
                            echo ""
                            dividing_line "-"
                            pause "Press any key to continue..."
                            ;;
                        6)
                            isexit=true
                            ;;
                        esac
                        break
                        ;;
                    esac
                else
                    :
                fi
                ;;
            esac
        fi
    done
}

# 返回值：如果刷新时间已过设定时长，则返回 false，否则返回 true
refresh_cooling() {
    local time=$(date +%s.%N)
    bc <<<"$time - $refresh_time > 0.1"
    if ((bc == 1)); then
        echo false
    else
        echo true
    fi
}

# 菜单类 ####################################################################################################

# 主菜单
__main_menu__() {
    # 显示页眉
    title "Ubuntu-CD Explorer"
    echo -e "[N]ew${TAB}[Del]ete${TAB}[M]ove(Cut)${TAB}[C]opy${TAB}[P]aste${TAB}[R]ename${TAB}[S]earch${TAB}pr[o]perties${TAB}re[F]resh${TAB}${red}[Q]uit$normal"
    dividing_line "-"
    echo -e "Current directory: $yellow$(pwd)$normal"

    # 处理文件列表
    # 仅需要刷新时处理，减少卡顿
    # FIXME 快速搜索内容变化时仍然会卡顿，将搜索栏优先刷新
    # TODO 快速搜索功能实现
    local time=$(date +%s.%N)
    if $refresh; then
        log_debug "refreshed"
        shopt -s nullglob # 设置nullglob选项，使没有匹配时返回空数组
        files=(*)         # 将当前目录下的所有文件和目录存入数组
        shopt -u nullglob # 取消nullglob选项，避免影响后续命令

        # 排序
        local sort_mode="${sort_options[$sort_setting]}"
        # TODO 倒序排列、其余排序方式
        if [ "$sort_mode" = "name" ]; then
            if [ "$sort_r" = false ]; then
                files=($(printf "%s\n" "${files[@]}" | sort))
            else
                files=($(printf "%s\n" "${files[@]}" | sort -r))
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
                    if [ "$sort_r" = false ]; then
                        sort -n
                    else
                        sort -nr
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
                    if [ "$sort_r" = false ]; then
                        sort -n
                    else
                        sort -nr
                    fi | cut -d ' ' -f2- # 按数值排序后提取文件名
            )
            files=("${sorted_files[@]}")
        fi

        files_form=() # 用于存储每行应该显示的内容
        local i=0
        for file in "${files[@]}"; do
            # 获取文件的修改日期
            local mtime="$(show_prop mt "$file")"
            # 获取文件的类型和大小
            local file_type=$(show_prop type "$file")
            local file_size=$(show_prop size "$file")
            files_form[i]=$(printf "%-30.29s %-30.29s %-30.29s %+15.29s" "$file" "$mtime" "$file_type" "$file_size")
            ((i++))
        done

        # 可以被选中的内容
        funcs=("Fast Search: $fast_search_name" "$(show_sort_by)" ".." "${files_form[@]}")

        refresh=false
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
            printf "%-30s %-30s %-30s %+15s" "Name" "Modified Date" "Type" "Size"
            echo ""
        fi
        ((i++))
    done

    # 显示页尾
    echo -e "$NORMAL"
    echo -e "$log_info"
}

# 新建菜单
__new_menu__() {
    # 显示页眉
    centering "New"
    dividing_line "="
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
    centering "Paste"
    dividing_line "-"
    echo -e "Target file: $yellow$target_file$normal"
    echo -e "Target directory: $yellow$target_dir$normal"
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
            "[$(show_bool "$mv_b")] -b: When the target file or directory exists, create a backup of it before performing the overwrite."
            "[$(show_bool "$mv_i")] -i: If the source directory or file specified to be moved has the same name as the target's directory or file, first ask whether to overwrite the old file."
            "[$(show_bool "$mv_f")] -f: If the source directory or file specified to be moved has the same name as the target's directory or file, the old file is overwritten directly."
            "[$(show_bool "$mv_n")] -n: Does not overwrite any pre-existing files or directories."
            "[$(show_bool "$mv_u")] -u: When the source file is newer than the target file or the target file does not exist, then perform the move operation."
            "Confirm"
            "Cancel"
        )
    elif [ "$mode" = "copy" ]; then
        : # TODO
    fi

    # 显示页面
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
    log_clr

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

# 参数：目标文件名 目标目录
paste_menu() {
    target_file=$1
    target_dir=$2

    funcs=()
    confirm_clr
    page="paste"
    cho=0
    log_clr

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
    if $1; then
        echo -ne "${blue}True$normal"
    else
        echo -ne "${red}False$normal"
    fi
}

handle_error() {
    local file_name=$1
    local error_message=$2
    case "$error_message" in
    *"Permission denied"*)
        echo -e "Permission denied: $file_name\n${yellow}You do not have sufficient privileges, please confirm the current user privileges or switch to a user with sufficient privileges. You can also contact the administrator for help.$normal"
        ;;
    *"No such file or directory"*)
        echo -e "No such file or directory: $file_name\n${yellow}The directory was not found, please check if it exists.$normal"
        ;;
    *"File exists"*)
        echo -e "File exists: $file_name\n${yellow}The file already exists, please choose another name.$normal"
        ;;
    *)
        echo -e "Unknown error: $file_name ($error_message)"
        ;;
    esac
}

# 日志类 ####################################################################################################

# TODO 将日志写入文件以支持显示更多内容
log() {
    if $debug;then
        log_info+="\n[$(date)] $1"
    else
        log_info="\n$(dividing_line "-")\n[$(date)] $1"
    fi
}
log_warn() {
    if $debug;then
        log_info+="\n[$(date)] ${YELLOW}${black}[WARNING]$NORMAL $1"
    else
        log_info="\n$(dividing_line "-")\n[$(date)] ${YELLOW}${black}[WARNING]$NORMAL $1"
    fi
}
log_err() {
    if $debug;then
        log_info+="\n[$(date)] ${RED}[ERROR]$NORMAL $1"
    else
        log_info="\n$(dividing_line "-")\n[$(date)] ${RED}[ERROR]$NORMAL $1"
    fi
}
log_debug() {
    if [ "$log_info" = "" ]; then
        log_clr
    fi
    log_info+="\n[$(date)] ${BLUE}[DEBUG]$NORMAL $1"
}
log_clr() {
    if $debug && [ "$log_info" != "" ];then
        log_info="\n$(dividing_line "-")\n"
    else
        log_info="\n$(dividing_line "-")\n"
    fi
}

confirm_clr() {
    # local confirms=("delete" "p")
    if [ "$confirm" != "" ]; then
        log_clr
        confirm=""
        # log_debug "${BASH_LINENO[0]}: confirm set to ''"
        
    fi
    # if [ "$(contains_element "$confirm" "${confirms[@]}")" != "" ]; then
    #     confirm=""
    # fi
}

show_what_has_been_pressed() {
    log_debug "Key pressed: '$key' (ASCII: $(printf %d "'$key")))"
}

# 初始化 ####################################################################################################

# 颜色转义字符，小写为字体颜色，大写为文字颜色
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

funcs=()           # 存储可选行
isexit=false       # 是否退出
refresh=true       # 是否刷新
debug=false        # 调试模式
cho=0              # 当前选择行
page="main"        # 当前页面
sort_setting=0     # 排序选项
sort_r=false       # 是否倒序排序
new_type_setting=0 # 新建类型选项
refresh_time=0     # 刷新时间

mv_b=false
mv_u=false
mv_n=false
mv_i=false
mv_f=false

for arg in "$@"; do
    case $arg in
    --debug)
        debug=true
        ;;
    *)
        echo "[$0] Unknown argument: $arg"
        echo "Usage:  [--debug]"
        exit 1
        ;;
    esac
done
if $debug; then
    log_debug "Debug mode is on"
fi

main_menu
