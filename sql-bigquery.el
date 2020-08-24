;;; sql-bigquery --- Adds Bigquery support to SQLi mode. -*- lexical-binding: t -*-

;; Copyright 2020- Martin Nowak <code+sql-bigquery@dawg.eu>

;; Author: Martin Nowak <code+sql-bigquery@dawg.eu>
;; Version: 0.5.0
;; Keywords: sql, bigquery
;; Package-Requires: ((emacs "24.4"))
;; URL: https://github.com/MartinNowak/sql-bigquery

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

(defgroup sql-bigquery nil
  "Use BigQuery with sql-interactive mode."
  :group 'SQL
  :prefix "sql-bigquery-")

(defcustom sql-bigquery-program "bq"
  "Command to start the BigQuery command interpreter."
  :type 'file
  :group 'sql-bigquery)

(defcustom sql-bigquery-login-params '(database)
  "Parameters needed to connect to BigQuery."
  :type 'sql-login-params
  :group 'sql-bigquery)

(defcustom sql-bigquery-options '("--format" "pretty")
  "List of options for `sql-bigquery-program'."
  :type '(repeat string)
  :group 'sql-bigquery)

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

(defun sql-bigquery-input-filter (string)
  "Turn input into a query command."
  (setq string (concat "query \"" string "\""))
  string)

;;;###autoload
(defun sql-bigquery (&optional buffer)
  "Run BigQuery as an inferior process.

The buffer with name BUFFER will be used or created."
  (interactive "P")
  (sql-product-interactive 'bigquery buffer))

(sql-add-product 'bigquery "BigQuery"
                 '(:free-software t
                   :list-all "SELECT * FROM INFORMATION_SCHEMA.SCHEMATA"
                   :list-table "SELECT * FROM %s.INFORMATION_SCHEMA.TABLES;"
                   :prompt-regexp "^[^>]*> "
                   :prompt-cont-regexp "^[ ]+-> "
                   :sqli-comint-func 'sql-bigquery-comint
                   :font-lock 'sql-mode-ansi-font-lock-keywords
                   :sqli-login sql-bigquery-login-params
                   :sqli-program 'sql-bigquery-program
                   :sqli-options 'sql-bigquery-options
                   :input-filter '(sql-escape-newlines-filter sql-bigquery-input-filter)))

(provide 'sql-bigquery)
;;; sql-bigquery.el ends here
