# Preserve upstream metadata as comments; keep dictionary rows and weights unchanged.
{ sub(/\r$/, "") }
!started {
    if ($0 ~ /^[[:space:]]*\.\.\.[[:space:]]*$/) { started = 1; next }
    if ($0 ~ /^#/ || $0 == "") print
    else print "# " $0
    next
}
{ print }
END {
    if (!started) {
        print "下载的词库缺少 Rime 数据分隔符，转换失败" > "/dev/stderr"
        exit 1
    }
}
