"""
Bank Transaction Simulator — Generates realistic banking metrics for Prometheus.
Simulates ICICI/HDFC-style transaction patterns:
  - UPI payments, NEFT/RTGS transfers, card transactions, ATM withdrawals
  - Peak hours (9AM-9PM), reduced traffic at night
  - Realistic failure rates (timeout, insufficient funds, fraud block)
  - Multiple branches/regions

Exposes metrics at :8000/metrics for Prometheus to scrape.
Run: python app.py
"""

import random
import time
import threading
from datetime import datetime

from flask import Flask
from prometheus_client import (
    Counter, Gauge, Histogram, Summary,
    generate_latest, CONTENT_TYPE_LATEST,
)

app = Flask(__name__)

# ═══════════════════════════════════════════════════════
# Prometheus Metrics — Banking Domain
# ═══════════════════════════════════════════════════════

# Transaction counters
transactions_total = Counter(
    'bank_transactions_total',
    'Total number of transactions',
    ['type', 'status', 'channel', 'region']
)

# Transaction amounts
transaction_amount = Histogram(
    'bank_transaction_amount_inr',
    'Transaction amount in INR',
    ['type', 'channel'],
    buckets=[100, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000, 500000, 1000000]
)

# Revenue (successful transaction amounts)
revenue_total = Counter(
    'bank_revenue_total_inr',
    'Total successful transaction amount in INR',
    ['type', 'region']
)

# Active users
active_users = Gauge(
    'bank_active_users',
    'Currently active users on the platform',
    ['channel']
)

# Response latency
response_time = Histogram(
    'bank_response_time_seconds',
    'Transaction processing time',
    ['type', 'status'],
    buckets=[0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0]
)

# Account balance (sample accounts)
account_balance = Gauge(
    'bank_account_balance_inr',
    'Account balance for sample accounts',
    ['account_id', 'account_type']
)

# Failed transaction reasons
failure_reasons = Counter(
    'bank_transaction_failures',
    'Transaction failure reasons',
    ['reason', 'type']
)

# Queue depth (pending transactions)
pending_queue = Gauge(
    'bank_pending_transactions',
    'Transactions waiting to be processed',
    ['type']
)

# Login attempts
login_attempts = Counter(
    'bank_login_attempts_total',
    'Login attempts',
    ['status', 'channel']
)

# API calls
api_calls = Counter(
    'bank_api_calls_total',
    'API calls to banking services',
    ['endpoint', 'method', 'status_code']
)

# System health
system_errors = Counter(
    'bank_system_errors_total',
    'Internal system errors',
    ['service', 'error_type']
)

# ═══════════════════════════════════════════════════════
# Configuration — Realistic Banking Patterns
# ═══════════════════════════════════════════════════════

TRANSACTION_TYPES = ['UPI', 'NEFT', 'RTGS', 'IMPS', 'CARD', 'ATM', 'CHEQUE']
CHANNELS = ['mobile_app', 'internet_banking', 'atm', 'branch', 'pos_terminal']
REGIONS = ['mumbai', 'delhi', 'bangalore', 'hyderabad', 'chennai', 'kolkata', 'pune', 'ahmedabad']
FAILURE_REASONS = [
    'insufficient_funds', 'timeout', 'fraud_blocked',
    'invalid_account', 'daily_limit_exceeded', 'bank_server_down',
    'incorrect_pin', 'expired_card', 'network_error'
]
API_ENDPOINTS = [
    '/api/v1/transfer', '/api/v1/balance', '/api/v1/statement',
    '/api/v1/upi/pay', '/api/v1/cards/transaction', '/api/v1/login',
    '/api/v1/beneficiary', '/api/v1/otp/verify'
]

# Amount ranges by transaction type (INR)
AMOUNT_RANGES = {
    'UPI': (10, 100000),
    'NEFT': (1000, 1000000),
    'RTGS': (200000, 10000000),
    'IMPS': (100, 500000),
    'CARD': (50, 200000),
    'ATM': (100, 25000),
    'CHEQUE': (5000, 5000000),
}

# Success rates by type (realistic)
SUCCESS_RATES = {
    'UPI': 0.96,
    'NEFT': 0.99,
    'RTGS': 0.995,
    'IMPS': 0.97,
    'CARD': 0.94,
    'ATM': 0.92,
    'CHEQUE': 0.88,
}

# Latency profiles (seconds) — mean, std
LATENCY_PROFILES = {
    'UPI': (0.3, 0.2),
    'NEFT': (2.0, 1.0),
    'RTGS': (1.5, 0.5),
    'IMPS': (0.5, 0.3),
    'CARD': (1.2, 0.8),
    'ATM': (3.0, 1.5),
    'CHEQUE': (5.0, 2.0),
}


def get_traffic_multiplier() -> float:
    """Simulate peak/off-peak hours. Peak = 9AM-9PM IST."""
    hour = datetime.now().hour
    if 9 <= hour <= 12:
        return 2.5  # Morning peak
    elif 12 < hour <= 14:
        return 1.8  # Lunch dip
    elif 14 < hour <= 18:
        return 2.2  # Afternoon
    elif 18 < hour <= 21:
        return 3.0  # Evening peak (UPI dinner payments)
    elif 21 < hour <= 23:
        return 1.2  # Late night
    else:
        return 0.4  # Night (ATM only)


def simulate_transaction():
    """Generate one realistic banking transaction."""
    txn_type = random.choices(
        TRANSACTION_TYPES,
        weights=[40, 10, 5, 15, 20, 8, 2],  # UPI dominates
        k=1
    )[0]

    channel = random.choice(CHANNELS)
    region = random.choice(REGIONS)

    # Determine success/failure
    success_rate = SUCCESS_RATES[txn_type]
    # Slightly lower success during peak hours (system strain)
    if get_traffic_multiplier() > 2.0:
        success_rate -= 0.02

    is_success = random.random() < success_rate
    status = 'success' if is_success else 'failed'

    # Generate amount
    min_amt, max_amt = AMOUNT_RANGES[txn_type]
    # Log-normal distribution (most transactions are small, few are large)
    amount = min(max_amt, max(min_amt, random.lognormvariate(
        (len(str(min_amt)) + len(str(max_amt))) / 2, 1.5
    )))
    amount = round(amount, 2)

    # Generate latency
    mean_lat, std_lat = LATENCY_PROFILES[txn_type]
    latency = max(0.01, random.gauss(mean_lat, std_lat))
    # Failed transactions often take longer (timeout)
    if not is_success and random.random() > 0.5:
        latency *= 3

    # Record metrics
    transactions_total.labels(type=txn_type, status=status, channel=channel, region=region).inc()
    transaction_amount.labels(type=txn_type, channel=channel).observe(amount)
    response_time.labels(type=txn_type, status=status).observe(latency)

    if is_success:
        revenue_total.labels(type=txn_type, region=region).inc(amount)
    else:
        reason = random.choice(FAILURE_REASONS)
        failure_reasons.labels(reason=reason, type=txn_type).inc()

    # API call metric
    endpoint = random.choice(API_ENDPOINTS)
    status_code = '200' if is_success else random.choice(['400', '408', '500', '503'])
    api_calls.labels(endpoint=endpoint, method='POST', status_code=status_code).inc()

    # Occasional system errors
    if random.random() < 0.005:
        service = random.choice(['payment-gateway', 'core-banking', 'fraud-engine', 'notification-service'])
        error_type = random.choice(['connection_timeout', 'null_pointer', 'out_of_memory', 'deadlock'])
        system_errors.labels(service=service, error_type=error_type).inc()


def simulate_logins():
    """Simulate login attempts."""
    channel = random.choice(['mobile_app', 'internet_banking'])
    success = random.random() < 0.92
    status = 'success' if success else 'failed'
    login_attempts.labels(status=status, channel=channel).inc()


def update_active_users():
    """Update active user gauges based on time of day."""
    multiplier = get_traffic_multiplier()
    base_users = {
        'mobile_app': 45000,
        'internet_banking': 12000,
        'atm': 3000,
        'branch': 1500,
        'pos_terminal': 8000,
    }
    for channel, base in base_users.items():
        users = int(base * multiplier * random.uniform(0.8, 1.2))
        active_users.labels(channel=channel).set(users)


def update_pending_queue():
    """Simulate transaction queue depth."""
    for txn_type in TRANSACTION_TYPES:
        # Higher queue during peak
        multiplier = get_traffic_multiplier()
        base_queue = {'UPI': 50, 'NEFT': 200, 'RTGS': 30, 'IMPS': 80, 'CARD': 40, 'ATM': 10, 'CHEQUE': 500}
        queue = int(base_queue.get(txn_type, 50) * multiplier * random.uniform(0.5, 1.5))
        pending_queue.labels(type=txn_type).set(queue)


def update_sample_accounts():
    """Update sample account balances."""
    accounts = [
        ('ACC001', 'savings', 250000),
        ('ACC002', 'savings', 85000),
        ('ACC003', 'current', 1500000),
        ('ACC004', 'salary', 120000),
        ('ACC005', 'fd', 5000000),
    ]
    for acc_id, acc_type, base_balance in accounts:
        # Fluctuate balance slightly
        balance = base_balance * random.uniform(0.95, 1.05)
        account_balance.labels(account_id=acc_id, account_type=acc_type).set(round(balance, 2))


def simulator_loop():
    """Main simulation loop — generates continuous traffic."""
    print("Bank Transaction Simulator started")
    print(f"Generating metrics at :8000/metrics")

    while True:
        multiplier = get_traffic_multiplier()
        # Transactions per second (base ~50 TPS, peak ~150 TPS)
        tps = int(50 * multiplier * random.uniform(0.7, 1.3))

        for _ in range(tps):
            simulate_transaction()

        # Logins (~10% of TPS)
        for _ in range(max(1, tps // 10)):
            simulate_logins()

        # Update gauges every second
        update_active_users()
        update_pending_queue()
        update_sample_accounts()

        time.sleep(1)


# ═══════════════════════════════════════════════════════
# Flask Endpoints
# ═══════════════════════════════════════════════════════

@app.route('/metrics')
def metrics():
    """Prometheus scrape endpoint."""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}


@app.route('/')
def index():
    return """
    <h1>Bank Transaction Simulator</h1>
    <p>Simulating ICICI/HDFC-style banking traffic.</p>
    <ul>
        <li><a href="/metrics">Prometheus Metrics</a></li>
        <li>Transaction types: UPI, NEFT, RTGS, IMPS, Card, ATM, Cheque</li>
        <li>Channels: Mobile App, Internet Banking, ATM, Branch, POS</li>
        <li>Regions: Mumbai, Delhi, Bangalore, Hyderabad, Chennai, Kolkata, Pune, Ahmedabad</li>
    </ul>
    <p>Traffic adjusts by time of day (peak 9AM-9PM IST).</p>
    """


@app.route('/health')
def health():
    return {"status": "healthy"}, 200


# ═══════════════════════════════════════════════════════
# Start
# ═══════════════════════════════════════════════════════

if __name__ == '__main__':
    # Start simulator in background thread
    simulator_thread = threading.Thread(target=simulator_loop, daemon=True)
    simulator_thread.start()

    # Start Flask (Prometheus scrapes this)
    app.run(host='0.0.0.0', port=8000, debug=False)
