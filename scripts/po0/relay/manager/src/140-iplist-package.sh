iplist_ready() {
    [[ -f "${IPLIST_DOC}" && -f "${IPLIST_MANIFEST}" ]]
}

iplist_region_record() {
    local id="$1"
    [[ -f "${IPLIST_MANIFEST}" ]] || return 1
    awk -F '\t' -v id="${id}" '$1 == id { print; exit }' "${IPLIST_MANIFEST}"
}

iplist_region_label() {
    local id="$1"
    local record name rel
    record="$(iplist_region_record "${id}" || true)"
    if [[ -n "${record}" ]]; then
        IFS=$'\t' read -r _ name rel _ <<< "${record}"
        printf '%s (%s)' "${name}" "${id}"
    else
        printf '%s (missing)' "${id}"
    fi
}

build_iplist_manifest_for_dir() {
    local root="$1"
    local doc="${root}/docs/cncity.md"
    local manifest="${root}/manifest.tsv"
    local tmp
    [[ -f "${doc}" ]] || {
        err "iplist 包缺少 docs/cncity.md。"
        return 1
    }
    make_temp_file "${manifest}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    awk -F '|' '
        function trim_value(s) {
            gsub(/^[ \t\r\n]+/, "", s)
            gsub(/[ \t\r\n]+$/, "", s)
            return s
        }
        NF >= 3 {
            name = trim_value($2)
            url = trim_value($3)
            if (name == "" || url == "" || url == "无") next
            if (url !~ /^https?:\/\// || url !~ /\.txt$/) next
            rel = url
            sub(/^.*\/iplist\//, "", rel)
            if (rel !~ /^data\/cncity\//) {
                sub(/^.*\/data\/cncity\//, "data/cncity/", rel)
            }
            if (rel !~ /^data\/cncity\//) next
            id = rel
            sub(/^.*\//, "", id)
            sub(/\.txt$/, "", id)
            gsub(/[^A-Za-z0-9._-]/, "_", id)
            print id "\t" name "\t" rel "\t" url
        }
    ' "${doc}" | sort -u > "${tmp}"
    [[ -s "${tmp}" ]] || {
        err "无法从 cncity.md 解析出地区列表。"
        return 1
    }
    while IFS=$'\t' read -r _ _ rel _; do
        [[ -f "${root}/${rel}" ]] || {
            err "iplist 包缺少数据文件：${rel}"
            return 1
        }
    done < "${tmp}"
    mv -f "${tmp}" "${manifest}"
}

import_iplist_package() {
    local package="$1"
    local tmpdir olddir ts
    package="$(trim "${package}")"
    [[ -f "${package}" ]] || {
        err "文件不存在：${package}"
        return 1
    }
    command -v tar &>/dev/null || {
        err "系统缺少 tar，无法解压 iplist 包。"
        return 1
    }
    make_temp_dir "${CONF_DIR}" "po0-iplist.import" || return 1
    tmpdir="${TEMP_DIR_RESULT}"
    case "${package}" in
        *.tar.gz|*.tgz)
            tar -xzf "${package}" -C "${tmpdir}" || return 1
            ;;
        *.tar)
            tar -xf "${package}" -C "${tmpdir}" || return 1
            ;;
        *)
            err "仅支持 .tar.gz、.tgz 或 .tar 格式。"
            return 1
            ;;
    esac
    [[ -f "${tmpdir}/docs/cncity.md" ]] || {
        err "压缩包根目录必须包含 docs/cncity.md。"
        return 1
    }
    build_iplist_manifest_for_dir "${tmpdir}" || return 1

    ts="$(date '+%Y%m%d_%H%M%S')"
    olddir="${IPLIST_DIR}.old.${ts}"
    [[ -d "${olddir}" ]] && rm -rf -- "${olddir}"
    [[ -d "${IPLIST_DIR}" ]] && mv "${IPLIST_DIR}" "${olddir}"
    mv "${tmpdir}" "${IPLIST_DIR}" || {
        [[ -d "${olddir}" ]] && mv "${olddir}" "${IPLIST_DIR}" 2>/dev/null || true
        return 1
    }
    TEMP_DIRS=("${TEMP_DIRS[@]/${tmpdir}/}")
    [[ -d "${olddir}" ]] && rm -rf -- "${olddir}"
    success "iplist 离线包已导入。"
}
