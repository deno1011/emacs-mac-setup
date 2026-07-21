;;; Starter EAR scheduler job -*- mode: emacs-lisp; lexical-binding: t; -*-
;;; This file is data read by `ear-scheduler-load-file'.

(:id "agent.learning.dreaming"
 :template "agent.learning.dreaming"
 :name "Agent learning dreaming"
 :description "Consolidate applied/materialized skill learnings into skill files and prune temporary learning pipeline edges after outcome evidence exists."
 :interval 86400
 :auto-start nil
 :runtime default
 :async nil
 :usage-limits (:max-model-calls 0
                :max-tool-calls 20
                :max-total-tokens 0
                :max-cost-usd 0.0)
 :args (:limit 20
        :dry-run t
        :delete-consolidated t
        :require-outcome t
        :created-by "agent.learning.dreaming"
        :metadata (:purpose "generic skill-learning consolidation maintenance")))
