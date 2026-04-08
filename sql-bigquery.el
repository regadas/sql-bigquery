;;; sql-bigquery.el --- Adds BigQuery support to SQLi mode. -*- lexical-binding: t -*-

;; Copyright 2020- Martin Nowak <code+sql-bigquery@dawg.eu>
;; Copyright 2024- Filipe Regadas <oss@regadas.email>

;; Author: Martin Nowak <code+sql-bigquery@dawg.eu>
;; Maintainer: Filipe Regadas <oss@regadas.email>
;; Version: 0.6.0
;; Keywords: sql, bigquery
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
;; queries. It depends on an installed and functional 'google-cloud-sdk'.

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

;; BigQuery-specific font-lock keywords following the 4-tier pattern
;; used by built-in sql.el products (types, statements, functions, modifiers).

(defvar sql-mode-bigquery-font-lock-keywords
  (eval-when-compile
    (list
     ;; Types
     (sql-font-lock-keywords-builder 'font-lock-type-face nil
      "int64" "float64" "numeric" "bignumeric" "bool" "string" "bytes"
      "date" "datetime" "time" "timestamp" "geography" "json" "array"
      "struct" "interval" "range")

     ;; Keywords and statements
     (sql-font-lock-keywords-builder 'font-lock-keyword-face nil
      "select" "from" "where" "group" "order" "having" "limit" "offset"
      "union" "intersect" "except" "join" "cross" "inner" "left" "right"
      "full" "outer" "on" "using" "with" "as" "create" "drop" "alter"
      "insert" "update" "delete" "merge" "truncate" "export" "qualify"
      "window" "partition" "pivot" "unpivot" "tablesample" "assert"
      "by" "all" "distinct" "and" "or" "not" "in" "between" "like"
      "is" "null" "true" "false" "case" "when" "then" "else" "end"
      "asc" "desc" "into" "values" "set" "exists" "any" "some"
      "for" "system_time" "of")

     ;; BigQuery-specific functions
     (sql-font-lock-keywords-builder 'font-lock-builtin-face nil
      "safe_cast" "cast" "ifnull" "nullif" "coalesce" "if" "iif"
      "count" "sum" "avg" "min" "max" "countif" "approx_count_distinct"
      "approx_quantiles" "approx_top_count" "approx_top_sum"
      "array_agg" "array_length" "array_to_string" "string_agg"
      "generate_array" "generate_date_array" "generate_timestamp_array"
      "unnest" "date_trunc" "timestamp_trunc" "datetime_trunc" "time_trunc"
      "date_diff" "timestamp_diff" "date_add" "date_sub"
      "format_date" "format_timestamp" "parse_date" "parse_timestamp"
      "current_date" "current_timestamp" "current_datetime" "extract"
      "farm_fingerprint" "regexp_contains" "regexp_extract"
      "regexp_extract_all" "regexp_replace" "safe_divide" "safe_multiply"
      "safe_negate" "safe_add" "safe_subtract" "error"
      "row_number" "rank" "dense_rank" "lead" "lag"
      "first_value" "last_value" "nth_value"
      "concat" "length" "lower" "upper" "trim" "ltrim" "rtrim"
      "substr" "replace" "reverse" "starts_with" "ends_with"
      "lpad" "rpad" "repeat" "format" "to_json_string"
      "abs" "sign" "round" "ceil" "floor" "mod" "pow" "sqrt" "log" "ln"
      "greatest" "least")

     ;; BigQuery-specific clauses and modifiers
     (sql-font-lock-keywords-builder 'font-lock-preprocessor-face nil
      "options" "replace" "respect" "ignore" "nulls"
      "rows" "preceding" "following" "unbounded" "current" "row" "over"
      "temp" "temporary" "table" "view" "materialized" "function"
      "procedure" "schema" "model" "external")))
  "BigQuery-specific keywords for font-lock.")

(defun sql-bigquery-completion-object (sqlbuf schema)
  "Return a list of completions for BigQuery using SQLBUF and SCHEMA."
  (sql-redirect-value
   sqlbuf
   (if schema
       (format "SELECT table_name FROM `%s`.INFORMATION_SCHEMA.TABLES;" schema)
     "SELECT schema_name FROM INFORMATION_SCHEMA.SCHEMATA;")
   "^|\\s-*\\([^|[:space:]]+\\)\\s-*|" 1))

(defun sql-bigquery-comint (product options &optional buffer-name)
  "Connect to BigQuery in a comint buffer.

PRODUCT is the sql product (bigquery). OPTIONS are any additional
options to pass to bigquery-shell. BUFFER-NAME is what you'd like
the SQLi buffer to be named."
  (let ((params (append `("shell")
                        (unless (string= "" sql-database)
                          `("--project_id", sql-database))
                        options)))
    (sql-comint product params buffer-name)))

(defun sql-bigquery-line-comments-to-block (sql-string)
  "Convert -- line comments to /* */ block comments in SQL-STRING."
  (replace-regexp-in-string "--\\(.*\\)$" "/*\\1 */" sql-string))

(defun sql-bigquery-collapse-lines (sql-string)
  "Collapse newlines in SQL-STRING to spaces."
  (replace-regexp-in-string "[\n\r]+" " " sql-string))

(defun sql-bigquery-input-filter (string)
  "Turn input STRING into a query command.
Wraps in single quotes so backtick identifiers are literal.
Embedded single quotes use POSIX shell escaping."
  (let ((escaped (mapconcat #'identity (split-string string "'") "'\\''")))
    (concat "query --nouse_legacy_sql '" escaped "'")))


(defun sql-bigquery-set-format (fmt)
  "Set BigQuery output format for the current session.
FMT is one of: pretty, json, csv, sparse, prettyjson."
  (interactive
   (list (completing-read "Format: "
                          '("pretty" "json" "csv" "sparse" "prettyjson")
                          nil t)))
  (setq sql-bigquery-options `("--quiet" "--format" ,fmt)))

;;;###autoload
(defun sql-bigquery (&optional buffer)
  "Run BigQuery as an inferior process.

The buffer with name BUFFER will be used or created."
  (interactive "P")
  (sql-product-interactive 'bigquery buffer))

(sql-add-product 'bigquery "BigQuery"
                 :free-software t
                 :list-all "SELECT * FROM INFORMATION_SCHEMA.SCHEMATA;"
                 :list-table "SELECT * FROM %s.INFORMATION_SCHEMA.TABLES;"
                 :prompt-regexp "^[a-zA-Z][a-zA-Z0-9_:-]*> "
                 :prompt-cont-regexp "^[ ]+-> "
                 :terminator '(";" . ";")
                 :completion-object 'sql-bigquery-completion-object
                 :sqli-comint-func 'sql-bigquery-comint
                 :font-lock 'sql-mode-bigquery-font-lock-keywords
                 :sqli-login sql-bigquery-login-params
                 :sqli-program 'sql-bigquery-program
                 :sqli-options 'sql-bigquery-options
                 :input-filter '(sql-bigquery-line-comments-to-block sql-bigquery-collapse-lines sql-bigquery-input-filter))

(provide 'sql-bigquery)
;;; sql-bigquery.el ends here
