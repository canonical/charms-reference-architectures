#!/usr/bin/env bash


function snapstore_proxy_postgres() {
    snap-proxy config proxy.db.connection=postgresql://snapproxy-user:snapproxy-password@localhost:5432/snapproxy-db
}

function snapstore_proxy_register() {
    CMD="snap-proxy reregister"

    DOMAIN="snapstore-proxy.canonical.internal\r"
    EMAIL="xyz@gmail.com\r"
    PASSWORD="<PWD>\r"

    CHOICE1="2\r"
    CHOICE2="4\r"
    CHOICE3="2\r"
    CHOICE4="4\r"

    expect <<EOF
log_user 1
spawn ${CMD}
set timeout 30

# Optional domain prompt
expect {
    "domain name of this snap proxy" {
        expect "> "
        sleep 5
        send "${DOMAIN}"
    }
    timeout {
        puts "Timed out waiting for domain prompt"; exit 1
    }
}

# Email input
expect {
    "Email:" {
        sleep 10; send "${EMAIL}"
    }
    timeout {
        puts "Timed out waiting for email prompt"; exit 1
    }
}

# Password prompt and input
expect {
    "Password:" {
        sleep 10; send "${PASSWORD}"
    }
    timeout {
        puts "Timed out waiting for password prompt"; exit 1
    }
}

# Prompt 1: Primary reason
expect {
  -re {(?s)Primary reason.*\n> } { sleep 10; send "${CHOICE1}" }
  timeout {
      puts "Timed out waiting for prompt1"; exit 1
  }
}

# Prompt 2: Company size
expect {
    -re {(?s)Size of your company.*\n>} { sleep 10; send "${CHOICE2}" }
    timeout { puts "Timed out waiting for prompt2"; exit 1 }
}

# Prompt 3: Type of deployment
expect {
    -re {(?s)Type of deployment.*\n>} { sleep 10; send "${CHOICE3}" }
    timeout { puts "Timed out waiting for prompt3"; exit 1 }
}

# Prompt 4: Size of deployment
expect {
    -re {(?s)Size of your deployment.*\n>} { sleep 10; send "${CHOICE4}" }
    timeout { puts "Timed out waiting for prompt4"; exit 1 }
}

sleep 10

expect eof
EOF
}

echo "127.0.0.1 snapstore-proxy.canonical.internal" | tee -a /etc/hosts

snapstore_proxy_postgres
sleep 10
snapstore_proxy_register

echo "Starting snap-store-proxy status..."
snap-store-proxy status || true

echo "Starting snap-store-proxy config..."
snap-store-proxy config || true

sed -i '/127\.0\.0\.1\s\+snapstore-proxy\.canonical\.internal/d' /etc/hosts
