#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "
    Usage: $(basename "${0}") [OPTIONS] USER@SERVER

    Options:
    -a, --address                Vault address. Default is https://vault.infinum.co:8200
    -k, --key                    Path to ssh key. Default is ~/.ssh/id_rsa. Script uses .pub key pair for signing and private key to initiate connection to the server
    -t, --token                  Github token used for auth. By default it is pulled from variable GITHUB_TOKEN
    -p, --port                   SSH port
    -s, --sign                   Sign a certificate and write it to temporary file. Don't login
    -h, --help                   Print this message

    Example:
    $(basename "${0}") user@123.45.67.89
    "
}

arguments() {
    if [ $# -lt 0 ]
    then
        usage
        exit 1
    fi

    while [[ $# -gt 0 ]]
    do
        case "$1" in
            -a|--address)
                VAULT_ADDRESS="${2}"
                shift
                ;;

            -k|--key)
                SSH_KEY_PATH="${2}"
                shift
                ;;

            -t|--token)
                GITHUB_TOKEN="${2}"
                shift
                ;;

            -p|--port)
                PORT="${2}"
                shift
                ;;

            -s|--sign)
                SIGN=1
                ;;

            -h|--help)
                usage
                exit 0
                ;;
            
            -*)
                echo "Invalid flag $1"
                usage
                exit 1
                ;;
            
            *)
                USER="${1%@*}"
                SERVER="${1##*@}"
                ;;
                
        esac
        shift
    done
}

precheck() {
    # Check if variables are set and error if empty
    VAULT_ADDRESS="${VAULT_ADDRESS:?UNSET}"
    SSH_KEY_PATH="${SSH_KEY_PATH:?UNSET}"
    GITHUB_TOKEN="${GITHUB_TOKEN:?UNSET}"
    PUBLIC_SSH_KEY_PATH="${PUBLIC_SSH_KEY_PATH:?UNSET}"
    USER="${USER:?UNSET}"
    SERVER="${SERVER:?UNSET}"

    #Check for public key
    if [[ ! -f "${PUBLIC_SSH_KEY_PATH}" ]]; then
        echo "[ERR] Public key not found at ""${SSH_KEY_PATH}"".pub"
        exit 1
    fi
}

vault_auth() {
    VAULT_PAYLOAD="{\"token\":\"${GITHUB_TOKEN}\"}"
    VAULT_TOKEN=$(curl -s -X POST -d "${VAULT_PAYLOAD}" "${VAULT_ADDRESS}"/v1/auth/github/login | jq -r .auth.client_token)
    VAULT_TOKEN="${VAULT_TOKEN:?UNSET}"
}

vault_sign_key() {
    SIGNED_KEY_PATH=$(mktemp)
    if RESPONSE=$(curl -s --fail --header "X-Vault-Token: ${VAULT_TOKEN}" -X POST -d '{"public_key": "'"$(cat "${PUBLIC_SSH_KEY_PATH}")"'"}' "${VAULT_ADDR}/v1/ssh/sign/${USER}"); then
        echo "${RESPONSE}" | jq -r .data.signed_key > "${SIGNED_KEY_PATH}"
    else
        echo "[ERR] Couldn't sign a key. Check if you are added to correct github team."
        echo "Script will try to log you in without signing the key. It will work if your key is authorized. If not, contact your PM to add you to github project"
    fi
}

login() {
    if [ "${PORT}" = "NULL" ]; then
        ssh -i "${SSH_KEY_PATH}" -i "${SIGNED_KEY_PATH}" "${USER}"@"${SERVER}"
    else
        ssh -i "${SSH_KEY_PATH}" -i "${SIGNED_KEY_PATH}" -p "${PORT}" "${USER}"@"${SERVER}"
    fi
}
main() {
    arguments "$@"

    VAULT_ADDRESS="${VAULT_ADDRESS:-https://vault.infinum.co:8200}"
    SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
    PUBLIC_SSH_KEY_PATH="${SSH_KEY_PATH}.pub"
    GITHUB_TOKEN="${GITHUB_TOKEN:-$GITHUB_TOKEN}"
    SIGN="${SIGN:-NULL}"
    PORT="${PORT:-NULL}"
    
    precheck
    vault_auth
    vault_sign_key

    if [ "${SIGN}" = "1" ]; then
        echo "${SIGNED_KEY_PATH}"
    else
        login
        rm -f "${SIGNED_KEY_PATH}"
    fi

}

main "$@"