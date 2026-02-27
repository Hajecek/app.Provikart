<?php
/**
 * API: Položky objednávek přihlášeného uživatele s datumem instalace (installation_date).
 * GET  /api/order_items_by_installation_date.php  – vrátí VŠECHNY položky s vyplněným installation_date
 * GET  /api/order_items_by_installation_date.php?installation_date=YYYY-MM-DD  – pouze položky s tímto datem
 *
 * Přihlášení: PHP session (web) NEBO API token (Bearer / GET token).
 * Odpověď: { "success": true, "items": [ { "installation_date", "item_name", "order_id", ... } ], "count": N }
 * Volitelně přidej do SELECT sloupec s číslem objednávky z tabulky orders (např. o.order_number AS order_number)
 * a do $items[]: 'order_number' => $row['order_number'] ?? null
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'Povolena je pouze metoda GET nebo POST.'], JSON_UNESCAPED_UNICODE);
    exit;
}

require_once __DIR__ . '/../config/app_config.php';
require_once __DIR__ . '/../auth/db_conn.php';

$user_id = null;

// 1) Zkusit API token (Bearer nebo GET token)
$apiToken = null;
if (!empty($_GET['token'])) {
    $apiToken = trim($_GET['token']);
} elseif (!empty($_SERVER['HTTP_AUTHORIZATION']) && preg_match('/Bearer\s+(\S+)/', $_SERVER['HTTP_AUTHORIZATION'], $m)) {
    $apiToken = trim($m[1]);
}

if ($apiToken !== null && $apiToken !== '') {
    $now = time();
    $stmt = mysqli_prepare($conn, 'SELECT user_id FROM api_tokens WHERE token = ? AND expires_at > ? LIMIT 1');
    if ($stmt) {
        mysqli_stmt_bind_param($stmt, 'si', $apiToken, $now);
        mysqli_stmt_execute($stmt);
        $result = mysqli_stmt_get_result($stmt);
        $row = $result ? mysqli_fetch_assoc($result) : null;
        mysqli_stmt_close($stmt);
        if ($row !== null) {
            $user_id = (int) $row['user_id'];
        }
    }
}

// 2) Pokud není platný token, zkusit session (web)
if ($user_id === null) {
    require_once __DIR__ . '/../auth/session_init.php';
    require_once __DIR__ . '/../auth/session_manager.php';
    \SessionManager::getInstance();
    if (isset($_SESSION['user_id'])) {
        $user_id = (int) $_SESSION['user_id'];
    }
}

if ($user_id === null) {
    http_response_code(401);
    echo json_encode(['success' => false, 'error' => 'Nejste přihlášeni. Odešlete platný API token nebo se přihlaste přes web.'], JSON_UNESCAPED_UNICODE);
    exit;
}

// Parametr installation_date (nepovinný) – z GET, POST nebo JSON těla
$installation_date_input = '';
if (!empty($_GET['installation_date'])) {
    $installation_date_input = trim((string) $_GET['installation_date']);
} elseif (!empty($_POST['installation_date'])) {
    $installation_date_input = trim((string) $_POST['installation_date']);
} else {
    $raw = file_get_contents('php://input');
    if ($raw !== false && $raw !== '') {
        $json = json_decode($raw, true);
        if (is_array($json) && isset($json['installation_date']) && $json['installation_date'] !== '') {
            $installation_date_input = trim((string) $json['installation_date']);
        }
    }
}

$filter_by_date = false;
$date_for_sql = null;
if ($installation_date_input !== '') {
    if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $installation_date_input, $m)) {
        $date_for_sql = $installation_date_input;
        $filter_by_date = true;
    } elseif (preg_match('/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/', $installation_date_input, $m)) {
        $date_for_sql = $m[3] . '-' . str_pad($m[2], 2, '0', STR_PAD_LEFT) . '-' . str_pad($m[1], 2, '0', STR_PAD_LEFT);
        $filter_by_date = true;
    }
    if ($filter_by_date && $date_for_sql === null) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Neplatný formát data. Použijte YYYY-MM-DD nebo DD.MM.YYYY.'], JSON_UNESCAPED_UNICODE);
        exit;
    }
}

// Položky objednávek uživatele s vyplněným installation_date
// Pro zobrazení skutečného čísla objednávky v aplikaci: přidej do SELECT sloupec z orders (např. o.order_number AS order_number)
// a do $items[] přidej 'order_number' => $row['order_number'] ?? null
$sql = "SELECT oi.id, oi.order_id, oi.item_name, oi.installation_date, oi.base_price, oi.discount, oi.commission, oi.status
        FROM order_items oi
        INNER JOIN orders o ON o.id = oi.order_id AND o.user_id = ?
        WHERE oi.installation_date IS NOT NULL AND oi.installation_date != ''
          AND STR_TO_DATE(oi.installation_date, '%d.%m.%Y') IS NOT NULL";
if ($filter_by_date && $date_for_sql !== null) {
    $sql .= " AND DATE(STR_TO_DATE(oi.installation_date, '%d.%m.%Y')) = ?";
}
$sql .= " ORDER BY STR_TO_DATE(oi.installation_date, '%d.%m.%Y') ASC, oi.id ASC";

$stmt = mysqli_prepare($conn, $sql);
if ($stmt === false) {
    error_log('API order_items_by_installation_date prepare failed: ' . mysqli_error($conn));
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'Chyba systému.'], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($filter_by_date && $date_for_sql !== null) {
    mysqli_stmt_bind_param($stmt, 'is', $user_id, $date_for_sql);
} else {
    mysqli_stmt_bind_param($stmt, 'i', $user_id);
}
mysqli_stmt_execute($stmt);
$result = mysqli_stmt_get_result($stmt);
$items = [];
while ($row = mysqli_fetch_assoc($result)) {
    $items[] = [
        'id' => (int) $row['id'],
        'order_id' => (int) $row['order_id'],
        'item_name' => $row['item_name'],
        'installation_date' => $row['installation_date'],
        'base_price' => (float) $row['base_price'],
        'discount' => (float) $row['discount'],
        'commission' => (float) $row['commission'],
        'status' => $row['status'],
    ];
}
mysqli_stmt_close($stmt);

$out = [
    'success' => true,
    'items' => $items,
    'count' => count($items),
];
if ($filter_by_date && $date_for_sql !== null) {
    $out['installation_date'] = $date_for_sql;
}
echo json_encode($out, JSON_UNESCAPED_UNICODE | JSON_NUMERIC_CHECK);
