/**
 * BetterDesk Console - Dashboard Routes
 */

const express = require("express");
const router = express.Router();
const db = require("../services/database");
const hbbsApi = require("../services/hbbsApi");
const keyService = require("../services/keyService");
const config = require("../config/config");
const { requireAuth } = require("../middleware/auth");

/**
 * GET / - Dashboard page
 */
router.get("/", requireAuth, (req, res) => {
  res.render("dashboard", {
    title: req.t("nav.dashboard"),
    activePage: "dashboard",
  });
});

/**
 * GET /api/stats - Get dashboard statistics
 */
router.get("/api/stats", requireAuth, async (req, res) => {
  try {
    // Get device stats from database
    const stats = db.getStats();

    // Get HBBS API health
    const hbbsHealth = await hbbsApi.getHealth();

    // Get public key info
    const publicKey = keyService.getPublicKey();

    res.json({
      success: true,
      data: {
        devices: stats,
        hbbs: hbbsHealth,
        publicKey: publicKey ? true : false,
      },
    });
  } catch (err) {
    console.error("Stats error:", err);
    res.status(500).json({
      success: false,
      error: req.t("errors.server_error"),
    });
  }
});

/**
 * GET /api/server/status - Get server status
 */
router.get("/api/server/status", requireAuth, async (req, res) => {
  try {
    const hbbsHealth = await hbbsApi.getHealth();

    // Check HBBR by trying to connect to port 21117
    let hbbrStatus = { status: "unknown" };
    try {
      const net = require("net");
      const hbbrCheck = await new Promise((resolve) => {
        const socket = new net.Socket();
        socket.setTimeout(2000);
        socket.on("connect", () => {
          socket.destroy();
          resolve({ status: "running" });
        });
        socket.on("error", () => resolve({ status: "stopped" }));
        socket.on("timeout", () => {
          socket.destroy();
          resolve({ status: "stopped" });
        });
        socket.connect(config.wsProxy.hbbrPort, config.wsProxy.hbbrHost);
      });
      hbbrStatus = hbbrCheck;
    } catch (e) {
      hbbrStatus = { status: "unknown" };
    }

    res.json({
      success: true,
      data: {
        hbbs: hbbsHealth,
        hbbr: hbbrStatus,
        api_port: parseInt(new URL(config.hbbsApiUrl).port, 10) || 21120,
        hbbs_port: config.wsProxy.hbbsPort,
        hbbr_port: config.wsProxy.hbbrPort,
      },
    });
  } catch (err) {
    console.error("Server status error:", err);
    res.status(500).json({
      success: false,
      error: req.t("errors.server_error"),
    });
  }
});

/**
 * POST /api/sync-status - Sync online status from HBBS API
 */
router.post("/api/sync-status", requireAuth, async (req, res) => {
  try {
    const result = await hbbsApi.syncOnlineStatus(db.getDb());

    res.json({
      success: true,
      data: result,
    });
  } catch (err) {
    console.error("Sync status error:", err);
    res.status(500).json({
      success: false,
      error: req.t("errors.server_error"),
    });
  }
});

module.exports = router;
