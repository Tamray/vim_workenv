(defun org-clock-report (&optional arg)
  "Create a table containing a report about clocked time.
If the cursor is inside an existing clocktable block, then the table
will be updated.  If not, a new clocktable will be inserted.  The scope
of the new clock will be subtree when called from within a subtree, and
file elsewhere.

When called with a prefix argument, move to the first clock table in the
buffer and update it."
  (interactive "P")
  (org-clock-remove-overlays)
  (when arg
    (org-find-dblock "clocktable")
    (org-show-entry))
  (if (org-in-clocktable-p)
      (goto-char (org-in-clocktable-p))
    (let ((props (if (ignore-errors
		       (save-excursion (org-back-to-heading)))
		     (list :name "clocktable" :scope 'file)
		     ;;(list :name "clocktable" :scope 'subtree) ;;comment by sbc
		   (list :name "clocktable"))))
      (org-create-dblock
       (org-combine-plists org-clock-clocktable-default-properties props))))
  (org-update-dblock))


(global-set-key (kbd "<f9> I") 'bh/punch-in)
(global-set-key (kbd "<f9> O") 'bh/punch-out)

;; Agenda clock report parameters
(setq org-agenda-clockreport-parameter-plist
      (quote (:link t :maxlevel 5 :fileskip0 t :compact t :formula % :scope file)))
(setq org-clock-clocktable-default-properties
      '(:maxlevel 5 :fileskip0 t :formula % :block today :scope file))
;;      (quote (:link t :maxlevel 5 :fileskip0 t :compact t :formula %)))
;;
;; Resume clocking tasks when emacs is restarted
(org-clock-persistence-insinuate)
;;
;; Yes it's long... but more is better ;)
(setq org-clock-history-length 28)
;; Resume clocking task on clock-in if the clock is open
(setq org-clock-in-resume t)
;; Do not change task states when clocking in
(setq org-clock-in-switch-to-state nil)
;; Separate drawers for clocking and logs
;;(setq org-drawers (quote ("PROPERTIES" "LOGBOOK")))
;; Save clock data and state changes and notes in the LOGBOOK drawer
(setq org-clock-into-drawer t)
;; Sometimes I change tasks I'm clocking quickly - this removes clocked tasks with 0:00 duration
(setq org-clock-out-remove-zero-time-clocks t)
;; Clock out when moving task to a done state
(setq org-clock-out-when-done t)
;; Save the running clock and all clock history when exiting Emacs, load it on startup
(setq org-clock-persist (quote history))
;; Enable auto clock resolution for finding open clocks
(setq org-clock-auto-clock-resolution (quote when-no-clock-is-running))
;; Include current clocking task in clock reports
(setq org-clock-report-include-clocking-task t)

(setq bh/keep-clock-running nil)

(defun bh/find-project-task ()
  "Move point to the parent (project) task if any"
  (let ((parent-task (save-excursion (org-back-to-heading) (point))))
    (while (org-up-heading-safe)
      (when (member (nth 2 (org-heading-components)) org-todo-keywords-1)
        (setq parent-task (point))))
    (goto-char parent-task)
    parent-task))

(defun bh/clock-in-and-set-project-as-default (pom)
  "Clock in the current task and set the parent project (if any) as the
default clocking task.  Agenda filter tags are set from the default task"
  ;; Find the parent project task if any and set that as the default
  (save-excursion
    (save-excursion
      (org-with-point-at pom
        (bh/find-project-task)
        (org-clock-in '(16))))
    (save-excursion
      (org-with-point-at pom
        (org-clock-in nil)))))

(defun bh/set-agenda-restriction-lock ()
  "Set filter to tags of POM, current task, or current project and refresh"
  (interactive)
  ;;
  ;; We're in the agenda
  ;;
  (let* ((pom (org-get-at-bol 'org-hd-marker))
         (tags (org-with-point-at pom (org-get-tags-at))))
    (if (equal major-mode 'org-agenda-mode)
        (if tags
            (org-with-point-at pom
              (bh/find-project-task)
              (org-agenda-set-restriction-lock))
          (org-agenda-remove-restriction-lock))
      (if (equal org-clock-default-task (org-id-find "eb155a82-92b2-4f25-a3c6-0304591af2f9" 'marker))
          (org-agenda-remove-restriction-lock)
        (org-with-point-at pom
          (bh/find-project-task)
          (org-agenda-set-restriction-lock))))))

(defun bh/punch-in ()
  "Start continuous clocking and set the default task to the project task
of the selected task.  If no task is selected set the Organization task as
the default task."
  (interactive)
  (setq bh/keep-clock-running t)
  (if (equal major-mode 'org-agenda-mode)
      ;;
      ;; We're in the agenda
      ;;
      (let* ((marker (org-get-at-bol 'org-hd-marker))
             (tags (org-with-point-at marker (org-get-tags-at))))
        (if tags
            (bh/clock-in-and-set-project-as-default marker)
          (bh/clock-in-organization-task-as-default)))
    ;;
    ;; We are not in the agenda
    ;;
    (save-restriction
      (widen)
      ; Find the tags on the current task
      (if (and (equal major-mode 'org-mode) (not (org-before-first-heading-p)))
          (bh/clock-in-and-set-project-as-default nil)
        (bh/clock-in-organization-task-as-default))))
  (bh/set-agenda-restriction-lock))

(defun bh/punch-out ()
  (interactive)
  (setq bh/keep-clock-running nil)
  (when (org-clock-is-active)
    (org-clock-out))
  (org-agenda-remove-restriction-lock))

(defun bh/clock-in-default-task ()
  (save-excursion
    (org-with-point-at org-clock-default-task
      (org-clock-in))))

(defun bh/clock-out-maybe ()
  (when (and bh/keep-clock-running
             (not org-clock-clocking-in)
             (marker-buffer org-clock-default-task)
             (not org-clock-resolving-clocks-due-to-idleness))
    (bh/clock-in-default-task)))

(add-hook 'org-clock-out-hook 'bh/clock-out-maybe 'append)


(require 'org-id)  
(defun bh/clock-in-task-by-id (id)
  "Clock in a task by id"
  (save-restriction
    (widen)
    (org-with-point-at (org-id-find id 'marker)
      (org-clock-in nil))))

(defun bh/clock-in-last-task ()
  "Clock in the interrupted task if there is one
Skip the default task and get the next one"
  (interactive)
  (let ((clock-in-to-task (if (org-clock-is-active)
                              (if (equal org-clock-default-task (cadr org-clock-history))
                                  (caddr org-clock-history)
                                (cadr org-clock-history))
                            (if (equal org-clock-default-task (car org-clock-history))
                                (cadr org-clock-history)
                              (car org-clock-history)))))
    (org-with-point-at clock-in-to-task
      (org-clock-in nil))))
