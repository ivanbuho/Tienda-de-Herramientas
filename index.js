const express = require('express');
const cors = require('cors');
const { WebcastPushConnection } = require('tiktok-live-connector');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;

// Estructura en memoria para almacenar las transmisiones activas y sus colas de eventos
// Formato: { username: { connection, comments: [], lastActive: timestamp } }
const activeConnections = {};

// Obtener o crear una conexión para un usuario de TikTok
function getOrCreateConnection(username) {
    const cleanUsername = username.toLowerCase().trim().replace('@', '');

    if (activeConnections[cleanUsername]) {
        activeConnections[cleanUsername].lastActive = Date.now();
        return activeConnections[cleanUsername];
    }

    const tiktokConnection = new WebcastPushConnection(cleanUsername, {
        processInitialData: false,
        enableExtendedGiftInfo: true
    });

    const sessionData = {
        connection: tiktokConnection,
        comments: [],
        lastActive: Date.now()
    };

    // Helper para guardar mensajes en la cola evitando desbordamiento de memoria
    const enqueueMessage = (message) => {
        sessionData.comments.push(message);
        if (sessionData.comments.length > 30) {
            sessionData.comments.shift(); // Mantiene máximo 30 eventos recientes
        }
    };

    // Escuchar comentarios
    tiktokConnection.on('chat', (data) => {
        enqueueMessage(`${data.nickname} dice: ${data.comment}`);
    });

    // Escuchar regalos
    tiktokConnection.on('gift', (data) => {
        if (data.giftType === 1 && !data.repeatEnd) return; // Filtrar ráfagas intermadias de regalos
        enqueueMessage(`${data.nickname} envió ${data.repeatCount || 1} ${data.giftName}`);
    });

    // Escuchar me gusta (Likes)
    tiktokConnection.on('like', (data) => {
        enqueueMessage(`${data.nickname} le dio me gusta al en vivo`);
    });

    // Escuchar cuando se unen espectadores
    tiktokConnection.on('member', (data) => {
        enqueueMessage(`${data.nickname} se unió a la transmisión`);
    });

    // Escuchar cuando comparten el directo
    tiktokConnection.on('share', (data) => {
        enqueueMessage(`${data.nickname} compartió el en vivo`);
    });

    // Manejo de desconexión y errores
    tiktokConnection.on('streamEnd', () => {
        enqueueMessage("La transmisión en vivo ha finalizado");
        delete activeConnections[cleanUsername];
    });

    tiktokConnection.on('error', (err) => {
        console.error(`Error en directo de @${cleanUsername}:`, err);
    });

    tiktokConnection.connect().then(state => {
        console.log(`Conectado exitosamente al directo de @${cleanUsername} (Room ID: ${state.roomId})`);
    }).catch(err => {
        console.error(`Error al intentar conectar con @${cleanUsername}:`, err);
        enqueueMessage("No se pudo conectar al en vivo. Verifica que el usuario esté transmitiendo.");
    });

    activeConnections[cleanUsername] = sessionData;
    return sessionData;
}

// Limpieza automática de conexiones inactivas para liberar memoria RAM cada 10 minutos
setInterval(() => {
    const now = Date.now();
    for (const username in activeConnections) {
        // Si no hay peticiones en 5 minutos, desconectar de TikTok
        if (now - activeConnections[username].lastActive > 5 * 60 * 1000) {
            pcallDisconnect(username);
        }
    }
}, 10 * 60 * 1000);

function pcallDisconnect(username) {
    try {
        if (activeConnections[username] && activeConnections[username].connection) {
            activeConnections[username].connection.disconnect();
        }
    } catch (e) {
        console.error(e);
    }
    delete activeConnections[username];
}

// Endpoint de prueba de salud
app.get('/', (req, res) => {
    res.send("Servidor TikVoz activo y listo.");
});

// Endpoint principal consumido por el complemento en Jieshuo
// Ejemplo: GET /getComments?username=usuario
app.get('/getComments', (req, res) => {
    const username = req.query.username;

    if (!username) {
        return res.status(400).json({ error: "Falta el parámetro 'username'" });
    }

    const session = getOrCreateConnection(username);
    
    if (session.comments.length > 0) {
        // Extrae y elimina el primer comentario de la cola
        const nextComment = session.comments.shift();
        return res.send(nextComment);
    } else {
        return res.send(""); // Devuelve texto vacío si no hay eventos nuevos
    }
});

app.listen(PORT, () => {
    console.log(`Servidor de TikVoz ejecutándose en el puerto ${PORT}`);
});
