#!/bin/bash

###########################################
# Part 5: Claude.ai Integration Module
###########################################

# Set error handling
set -e
trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Source common functions if this script is part of the main script
if [ -f "/opt/ansible-vpn/common/functions.sh" ]; then
    source "/opt/ansible-vpn/common/functions.sh"
fi

# Directory setup for Claude.ai integration
CLAUDE_CONFIG_DIR="/opt/ansible-vpn/claude-integration"
CLAUDE_PLAYBOOK_DIR="${CLAUDE_CONFIG_DIR}/playbooks"
CLAUDE_ERROR_DB="${CLAUDE_CONFIG_DIR}/error_patterns.db"

setup_claude_directories() {
    log_info "Setting up Claude.ai integration directories"
    mkdir -p "${CLAUDE_CONFIG_DIR}"
    mkdir -p "${CLAUDE_PLAYBOOK_DIR}"
    mkdir -p "${CLAUDE_CONFIG_DIR}/credentials"
    mkdir -p "${CLAUDE_CONFIG_DIR}/solutions"
}

create_claude_playbook() {
    cat > "${CLAUDE_PLAYBOOK_DIR}/claude_integration.yml" << 'EOL'
---
- name: Claude.ai Integration Setup
  hosts: localhost
  become: yes
  vars_files:
    - /opt/ansible-vpn/vars/claude_credentials.yml

  tasks:
    - name: Verify Claude.ai credentials
      block:
        - name: Check API credentials
          uri:
            url: "{{ claude_api_endpoint }}/verify"
            method: POST
            headers:
              Authorization: "Bearer {{ claude_api_key }}"
            validate_certs: yes
            status_code: 200
          register: api_check
          ignore_errors: yes

        - name: Store verification status
          set_fact:
            claude_verified: "{{ api_check is success }}"

    - name: Setup Error Detection System
      block:
        - name: Create error patterns database
          copy:
            content: |
              {
                "patterns": [],
                "solutions": [],
                "history": []
              }
            dest: "{{ claude_config_dir }}/error_patterns.json"
            mode: '0600'
          when: not ansible_check_mode

    - name: Configure AI Assistant Interface
      template:
        src: templates/claude_config.j2
        dest: /opt/ansible-vpn/config/claude_assistant.conf
        mode: '0644'

    - name: Setup Error Handling Integration
      include_tasks: tasks/error_handler.yml

    - name: Configure Solution Implementation System
      include_tasks: tasks/solution_implementation.yml
EOL
}

setup_error_handling() {
    cat > "${CLAUDE_PLAYBOOK_DIR}/tasks/error_handler.yml" << 'EOL'
---
- name: Configure Error Detection and Analysis
  block:
    - name: Install Python dependencies for error analysis
      pip:
        name:
          - pandas
          - scikit-learn
          - nltk
        state: present

    - name: Setup Error Collection Service
      template:
        src: templates/error_collector.service.j2
        dest: /etc/systemd/system/error-collector.service
        mode: '0644'

    - name: Start Error Collection Service
      systemd:
        name: error-collector
        state: started
        enabled: yes
        daemon_reload: yes

    - name: Configure Error Analysis Engine
      template:
        src: templates/error_analysis.conf.j2
        dest: /opt/ansible-vpn/config/error_analysis.conf
        mode: '0644'
EOL
}

setup_solution_implementation() {
    cat > "${CLAUDE_PLAYBOOK_DIR}/tasks/solution_implementation.yml" << 'EOL'
---
- name: Configure Solution Implementation System
  block:
    - name: Create Solution Templates Directory
      file:
        path: /opt/ansible-vpn/templates/solutions
        state: directory
        mode: '0755'

    - name: Setup Solution Validation Framework
      template:
        src: templates/solution_validator.py.j2
        dest: /opt/ansible-vpn/scripts/solution_validator.py
        mode: '0755'

    - name: Configure Solution Database
      copy:
        content: |
          {
            "implemented_solutions": [],
            "success_metrics": {},
            "validation_rules": {}
          }
        dest: /opt/ansible-vpn/data/solutions.json
        mode: '0644'

    - name: Setup Implementation Pipeline
      template:
        src: templates/implementation_pipeline.yml.j2
        dest: "{{ claude_config_dir }}/implementation_pipeline.yml"
        mode: '0644'
EOL
}

create_web_interface() {
    # Create React component for Claude.ai settings
    cat > "/opt/ansible-vpn/frontend/src/components/ClaudeSettings.jsx" << 'EOL'
import React, { useState, useEffect } from 'react';
import { useFormik } from 'formik';
import * as Yup from 'yup';
import axios from 'axios';
import { toast } from 'react-toastify';

const ClaudeSettings = () => {
  const [isConfigured, setIsConfigured] = useState(false);

  const formik = useFormik({
    initialValues: {
      apiKey: '',
      organizationId: '',
      model: 'claude-3-opus-20240229',
    },
    validationSchema: Yup.object({
      apiKey: Yup.string().required('API Key is required'),
      organizationId: Yup.string().required('Organization ID is required'),
      model: Yup.string().required('Model selection is required'),
    }),
    onSubmit: async (values) => {
      try {
        await axios.post('/api/claude/configure', values);
        toast.success('Claude.ai configuration updated successfully');
        setIsConfigured(true);
      } catch (error) {
        toast.error('Failed to update Claude.ai configuration');
        console.error('Configuration error:', error);
      }
    },
  });

  return (
    <div className="p-6 bg-white rounded-lg shadow">
      <h2 className="text-2xl font-bold mb-4">Claude.ai Integration Settings</h2>
      <form onSubmit={formik.handleSubmit}>
        {/* Form fields here */}
      </form>
    </div>
  );
};

export default ClaudeSettings;
EOL
}

setup_api_endpoints() {
    # Create Express.js API endpoints for Claude.ai integration
    cat > "/opt/ansible-vpn/backend/routes/claude.js" << 'EOL'
const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const { authenticate } = require('../middleware/auth');

router.post('/configure', authenticate, async (req, res) => {
    try {
        const { apiKey, organizationId, model } = req.body;
        
        // Execute Ansible playbook to update configuration
        const command = `ansible-playbook ${CLAUDE_PLAYBOOK_DIR}/claude_integration.yml -e "claude_api_key=${apiKey} claude_org_id=${organizationId} claude_model=${model}"`;
        
        exec(command, (error, stdout, stderr) => {
            if (error) {
                console.error(`Ansible execution error: ${error}`);
                return res.status(500).json({ error: 'Configuration failed' });
            }
            res.json({ message: 'Configuration updated successfully' });
        });
    } catch (error) {
        res.status(500).json({ error: 'Internal server error' });
    }
});

module.exports = router;
EOL
}

main() {
    log_info "Starting Claude.ai integration setup"
    
    # Setup required directories
    setup_claude_directories
    
    # Create Ansible playbooks
    create_claude_playbook
    setup_error_handling
    setup_solution_implementation
    
    # Setup web interface components
    create_web_interface
    setup_api_endpoints
    
    # Run initial playbook
    ansible-playbook "${CLAUDE_PLAYBOOK_DIR}/claude_integration.yml" --check
    
    log_info "Claude.ai integration setup completed"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
