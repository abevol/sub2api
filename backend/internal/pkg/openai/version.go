package openai

import (
	"strconv"
	"strings"
)

// NormalizeCodexVersion 校验并归一化 Codex CLI 版本号。
// 合法格式为 X.Y.Z，每部分是非负整数。非法或空串返回 ""。
func NormalizeCodexVersion(v string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return ""
	}
	parts := strings.Split(v, ".")
	if len(parts) != 3 {
		return ""
	}
	for _, p := range parts {
		if _, err := strconv.Atoi(p); err != nil {
			return ""
		}
	}
	return v
}
