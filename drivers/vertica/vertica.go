// Package vertica defines and registers usql's Vertica driver.
//
// See: https://github.com/vertica/vertica-sql-go
package vertica

import (
	"context"
	"os"
	"regexp"
	"strings"

	_ "github.com/vertica/vertica-sql-go" // DRIVER
	"github.com/vertica/vertica-sql-go/logger"
	"github.com/xo/usql/drivers"
)

func init() {
	// turn off logging
	if os.Getenv("VERTICA_SQL_GO_LOG_LEVEL") == "" {
		logger.SetLogLevel(logger.NONE)
	}
	errCodeRE := regexp.MustCompile(`(?i)^\[([0-9a-z]+)\]\s+(.+)`)
	drivers.Register("vertica", drivers.Driver{
		AllowDollar:            true,
		AllowMultilineComments: true,
		Version: func(ctx context.Context, db drivers.DB) (string, error) {
			var ver string
			if err := db.QueryRowContext(ctx, `SELECT version()`).Scan(&ver); err != nil {
				return "", err
			}
			return ver, nil
		},
		ChangePassword: func(db drivers.DB, user, newpw, _ string) error {
			_, err := db.Exec(`ALTER USER ` + user + ` IDENTIFIED BY '` + newpw + `'`)
			return err
		},
		Err: func(err error) (string, string) {
			msg := strings.TrimSpace(strings.TrimPrefix(err.Error(), "Error:"))
			if m := errCodeRE.FindAllStringSubmatch(msg, -1); m != nil {
				return m[0][1], strings.TrimSpace(m[0][2])
			}
			return "", msg
		},
		IsPasswordErr: func(err error) bool {
			return strings.HasSuffix(strings.TrimSpace(err.Error()), "Invalid username or password")
		},
	})
}
