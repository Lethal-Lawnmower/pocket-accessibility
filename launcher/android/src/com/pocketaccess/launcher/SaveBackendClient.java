package com.pocketaccess.launcher;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;

/**
 * The editor's end of the save backend (src/access/AndroidSaveBackend.lua): one JSON
 * line each way over a socket on this device only.  Other apps can reach a local port,
 * so the backend must first present the one-time token it was started with, and the
 * port takes only one connection.  Methods block, so they are called off the UI thread.
 */
final class SaveBackendClient {
    private static final int CONNECT_TIMEOUT_MILLIS = 60_000;

    private final ServerSocket server;
    private final String token;
    private Socket socket;
    private BufferedReader reader;
    private OutputStream writer;
    private int nextId = 1;

    SaveBackendClient() throws IOException {
        // the same address the backend connects to; Android's default loopback can be IPv6
        server = new ServerSocket(0, 1, InetAddress.getByAddress(new byte[] {127, 0, 0, 1}));
        byte[] random = new byte[16];
        new SecureRandom().nextBytes(random);
        StringBuilder hex = new StringBuilder();
        for (byte value : random) hex.append(String.format("%02x", value));
        token = hex.toString();
    }

    int port() {
        return server.getLocalPort();
    }

    String token() {
        return token;
    }

    /** Waits for the game's activity to start the backend and connect. */
    void waitForBackend() throws IOException {
        server.setSoTimeout(CONNECT_TIMEOUT_MILLIS);
        Socket accepted = server.accept();
        BufferedReader acceptedReader = new BufferedReader(
            new InputStreamReader(accepted.getInputStream(), StandardCharsets.UTF_8));
        if (!token.equals(acceptedReader.readLine())) {
            accepted.close();
            throw new IOException("the wrong program answered");
        }
        socket = accepted;
        reader = acceptedReader;
        writer = accepted.getOutputStream();
    }

    synchronized JSONObject send(String command, JSONObject arguments) throws IOException, JSONException {
        JSONObject request = arguments == null ? new JSONObject() : arguments;
        request.put("cmd", command);
        request.put("id", nextId++);
        writer.write((request.toString() + "\n").getBytes(StandardCharsets.UTF_8));
        writer.flush();
        String line = reader.readLine();
        if (line == null) throw new IOException("the save backend stopped");
        return new JSONObject(line);
    }

    /** The backend exits when its socket closes. */
    void close() {
        try {
            server.close();
        } catch (IOException ignored) {
            // nothing more to do while closing
        }
        try {
            if (socket != null) socket.close();
        } catch (IOException ignored) {
            // nothing more to do while closing
        }
    }
}
