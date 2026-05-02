;;; sql-bigquery.el --- Adds BigQuery support to SQLi mode -*- lexical-binding: t -*-

;; Copyright 2020- Martin Nowak <code+sql-bigquery@dawg.eu>
;; Copyright 2024- Filipe Regadas <oss@regadas.email>

;; Author: Martin Nowak <code+sql-bigquery@dawg.eu>
;; Maintainer: Filipe Regadas <oss@regadas.email>
;; Version: 0.6.0
;; Keywords: languages, sql, bigquery
;; Package-Requires: ((emacs "25.1"))
;; URL: https://github.com/regadas/sql-bigquery

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation, either version 3 of the License, or (at your option) any later
;; version.

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.

;; You should have received a copy of the GNU General Public License along with
;; this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package adds comint support for the BigQuery CLI shell to run
;; queries.  It depends on an installed and functional 'google-cloud-sdk'.

;;; Code:

(require 'sql)
(require 'seq)

(defgroup sql-bigquery nil
  "Use BigQuery with sql-interactive mode."
  :group 'sql
  :prefix "sql-bigquery-")

(defcustom sql-bigquery-program "bq"
  "Command to start the BigQuery command interpreter."
  :type 'file
  :group 'sql-bigquery)

(defcustom sql-bigquery-login-params '(database)
  "Parameters needed to connect to BigQuery."
  :type '(repeat symbol)
  :group 'sql-bigquery)

(defcustom sql-bigquery-options '("--quiet" "--format" "pretty")
  "List of options for `sql-bigquery-program'."
  :type '(repeat string)
  :group 'sql-bigquery)

;; BigQuery-specific font-lock keywords following the 5-tier pattern
;; used by built-in sql.el products.

(defvar sql-bigquery-font-lock-keywords
  (eval-when-compile
    (list
     ;; Types
     (sql-font-lock-keywords-builder 'font-lock-type-face nil
      "int32" "int64" "float32" "float64" "numeric" "bignumeric"
      "bool" "string" "bytes"
      "date" "datetime" "time" "timestamp"
      "geography" "json" "array" "struct" "interval" "range" "vector")

     ;; Constants
     (sql-font-lock-keywords-builder 'font-lock-constant-face nil
      "true" "false" "null")

     ;; Keywords and statements
     (sql-font-lock-keywords-builder 'font-lock-keyword-face nil
      "select" "from" "where" "group" "order" "having" "limit" "offset"
      "union" "intersect" "except" "join" "cross" "inner" "left" "right"
      "full" "outer" "natural" "on" "using" "with" "recursive" "as"
      "create" "drop" "alter" "insert" "update" "delete" "merge" "truncate"
      "export" "qualify" "window" "partition" "pivot" "unpivot"
      "tablesample" "assert"
      "by" "all" "distinct" "and" "or" "not" "in" "between" "like"
      "is" "case" "when" "then" "else" "end"
      "asc" "desc" "into" "values" "set" "exists" "any" "some"
      "for" "system_time" "of"
      "rollup" "cube" "grouping" "lateral"
      ;; Scripting
      "declare" "begin" "loop" "while" "repeat" "if" "elseif"
      "iterate" "leave" "continue" "break" "return" "call" "raise"
      "exception" "execute" "immediate")

     ;; BigQuery-specific functions
     (sql-font-lock-keywords-builder 'font-lock-builtin-face nil
      "safe_cast" "cast" "ifnull" "nullif" "coalesce"
      "count" "sum" "avg" "min" "max" "countif" "any_value"
      "logical_and" "logical_or"
      "approx_count_distinct" "approx_quantiles" "approx_top_count"
      "approx_top_sum"
      "array_agg" "array_length" "array_to_string" "array_concat"
      "array_reverse" "string_agg"
      "generate_array" "generate_date_array" "generate_timestamp_array"
      "generate_uuid"
      "unnest"
      ;; Date/time
      "date_trunc" "timestamp_trunc" "datetime_trunc" "time_trunc"
      "date_diff" "timestamp_diff" "datetime_diff" "time_diff"
      "date_add" "date_sub" "timestamp_add" "timestamp_sub"
      "datetime_add" "datetime_sub" "time_add" "time_sub"
      "format_date" "format_timestamp" "format_datetime" "format_time"
      "parse_date" "parse_timestamp" "parse_datetime" "parse_time"
      "current_date" "current_timestamp" "current_datetime" "extract"
      ;; String
      "concat" "length" "lower" "upper" "trim" "ltrim" "rtrim"
      "substr" "replace" "reverse" "starts_with" "ends_with"
      "lpad" "rpad" "repeat" "format" "to_json_string"
      ;; Regex
      "regexp_contains" "regexp_extract" "regexp_extract_all" "regexp_replace"
      ;; Hash / encoding
      "farm_fingerprint" "md5" "sha1" "sha256" "sha512"
      "to_hex" "from_hex" "to_base64" "from_base64"
      ;; JSON
      "json_extract" "json_extract_scalar" "json_extract_array"
      "json_value" "json_query" "json_query_array"
      "to_json" "parse_json" "json_type"
      ;; Math / safe
      "safe_divide" "safe_multiply" "safe_negate" "safe_add" "safe_subtract"
      "abs" "sign" "round" "ceil" "floor" "mod" "pow" "sqrt" "log" "ln"
      "greatest" "least"
      ;; Window / analytic
      "row_number" "rank" "dense_rank" "lead" "lag"
      "ntile" "percent_rank" "cume_dist"
      "percentile_cont" "percentile_disc"
      "first_value" "last_value" "nth_value"
      ;; Geography
      "st_geogpoint" "st_distance" "st_contains" "st_intersects"
      "st_area" "st_length" "st_geogfromtext" "st_astext" "st_asgeojson"
      ;; Net
      "net.ip_from_string" "net.safe_ip_from_string" "net.host"
      "net.reg_domain"
      ;; Misc
      "error")

     ;; BigQuery-specific clauses and modifiers
     (sql-font-lock-keywords-builder 'font-lock-preprocessor-face nil
      "options" "respect" "ignore" "nulls"
      "rows" "preceding" "following" "unbounded" "current" "row" "over"
      "temp" "temporary" "table" "view" "materialized" "function"
      "procedure" "schema" "model" "external"
      "cluster" "returns" "language" "deterministic"
      "remote" "connection" "clone" "snapshot" "copy")))
  "BigQuery-specific keywords for font-lock.")

;;; Quote-aware SQL transformations
;;
;; These functions track quoted contexts (single, double, triple-quoted,
;; and backtick identifiers) to avoid corrupting string literals.

(defun sql-bigquery--in-quoted-context-at-p (pos)
  "Return non-nil if buffer position POS is inside a quoted context.
Scans from `point-min' to POS in the current buffer.  Must be
called with a buffer whose content is the SQL being transformed."
  (let (in-quote)
    (save-excursion
      (goto-char (point-min))
      (while (< (point) pos)
        (let ((ch (char-after)))
          (cond
           (in-quote
            (when (eq ch (car in-quote))
              (if (and (cdr in-quote)  ; triple-quote
                       (<= (+ (point) 2) (point-max))
                       (eq (char-after (+ (point) 1)) ch)
                       (eq (char-after (+ (point) 2)) ch))
                  (progn (setq in-quote nil) (forward-char 2))
                (unless (cdr in-quote)
                  (setq in-quote nil)))))
           ;; Triple-quoted strings
           ((and (memq ch '(?' ?\"))
                 (<= (+ (point) 2) (point-max))
                 (eq (char-after (+ (point) 1)) ch)
                 (eq (char-after (+ (point) 2)) ch))
            (setq in-quote (cons ch t))
            (forward-char 2))
           ;; Single/double-quoted strings and backtick identifiers
           ((memq ch '(?' ?\" ?`))
            (setq in-quote (cons ch nil)))))
        (forward-char 1)))
    in-quote))

(defun sql-bigquery-line-comments-to-block (sql-string)
  "Convert -- line comments to /* */ block comments in SQL-STRING.
Preserves -- inside string literals and backtick-quoted identifiers."
  (with-temp-buffer
    (insert sql-string)
    (goto-char (point-min))
    (while (re-search-forward "--" nil t)
      (unless (sql-bigquery--in-quoted-context-at-p (match-beginning 0))
        (let ((start (match-beginning 0))
              (end (line-end-position)))
          (let ((body (buffer-substring-no-properties (point) end)))
            (delete-region start end)
            (goto-char start)
            (insert "/*" body " */")))))
    (buffer-string)))

(defun sql-bigquery-collapse-lines (sql-string)
  "Collapse newlines in SQL-STRING to spaces.
Preserves newlines inside string literals."
  (with-temp-buffer
    (insert sql-string)
    (goto-char (point-min))
    (while (re-search-forward "[\n\r]+" nil t)
      (unless (sql-bigquery--in-quoted-context-at-p (match-beginning 0))
        (replace-match " ")))
    (buffer-string)))

(defun sql-bigquery--wrap-query (sql)
  "Wrap SQL in a bq shell query command with standard SQL mode.
Escapes single quotes using POSIX shell escaping."
  (let ((escaped (mapconcat #'identity (split-string sql "'") "'\\''")))
    (concat "query --nouse_legacy_sql '" escaped "'")))

(defun sql-bigquery-input-filter (string)
  "Turn input STRING into a bq shell query command."
  (sql-bigquery--wrap-query string))

(defun sql-bigquery-completion-object (sqlbuf schema)
  "Return a list of completions for BigQuery using SQLBUF and SCHEMA.
Wraps queries with `query --nouse_legacy_sql' since `sql-redirect-value'
bypasses the input-filter chain."
  (sql-redirect-value
   sqlbuf
   (sql-bigquery--wrap-query
    (if schema
        (format "SELECT table_name FROM `%s`.INFORMATION_SCHEMA.TABLES" schema)
      "SELECT schema_name FROM INFORMATION_SCHEMA.SCHEMATA"))
   "^|\\s-*\\([^|[:space:]]+\\)\\s-*|" 1))

(defun sql-bigquery-comint (product options &optional buffer-name)
  "Connect to BigQuery in a comint buffer.

PRODUCT is the sql product (bigquery).  OPTIONS are any additional
options to pass to bigquery-shell.  BUFFER-NAME is what you'd like
the SQLi buffer to be named."
  (let ((params (append '("shell")
                        (unless (string= "" sql-database)
                          (list "--project_id" sql-database))
                        options))
        ;; Use pipe instead of PTY to avoid line-length truncation
        ;; for long queries collapsed to a single line.
        (process-connection-type nil))
    (sql-comint product params buffer-name)
    ;; Suppress sql-send-magic-terminator: it defaults to sending ";"
    ;; as a separate command, which bq shell executes as a broken query.
    ;; The "." regexp matches any non-empty input, so the terminator
    ;; is always considered already present and never sent.
    ;; sql-comint leaves us in the new SQLi buffer.
    (setq-local sql-send-terminator '("." . ""))))


(defun sql-bigquery-set-format (fmt)
  "Set BigQuery output format for future sessions.
FMT is one of: pretty, json, csv, sparse, prettyjson.
Does not affect the currently running bq shell process."
  (interactive
   (list (completing-read "Format: "
                          '("pretty" "json" "csv" "sparse" "prettyjson")
                          nil t)))
  (let ((opts sql-bigquery-options)
        result)
    (while opts
      (if (equal (car opts) "--format")
          (setq opts (cddr opts))
        (push (pop opts) result)))
    (setq sql-bigquery-options
          (nconc (nreverse result) (list "--format" fmt)))))

;;;###autoload
(defun sql-bigquery (&optional buffer)
  "Run BigQuery as an inferior process.

The buffer with name BUFFER will be used or created."
  (interactive "P")
  (sql-product-interactive 'bigquery buffer))

;; Remove stale registration so the file can be reloaded cleanly.
(setq sql-product-alist (assq-delete-all 'bigquery sql-product-alist))
(sql-add-product 'bigquery "BigQuery"
                 :free-software t
                 :list-all "query --nouse_legacy_sql 'SELECT schema_name FROM INFORMATION_SCHEMA.SCHEMATA'"
                 :list-table "query --nouse_legacy_sql 'SELECT table_name FROM `%s`.INFORMATION_SCHEMA.TABLES'"
                 :prompt-regexp "^[a-z][a-z0-9._:-]+> "
                 :terminator '("." . "")
                 :completion-object 'sql-bigquery-completion-object
                 :sqli-comint-func 'sql-bigquery-comint
                 :font-lock 'sql-bigquery-font-lock-keywords
                 :sqli-login sql-bigquery-login-params
                 :sqli-program 'sql-bigquery-program
                 :sqli-options 'sql-bigquery-options
                 :input-filter '(sql-bigquery-line-comments-to-block
                                 sql-bigquery-collapse-lines
                                 sql-bigquery-input-filter))

(provide 'sql-bigquery)
;;; sql-bigquery.el ends here
