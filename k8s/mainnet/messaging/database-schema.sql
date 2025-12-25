-- Conversation table
CREATE TABLE IF NOT EXISTS "Conversation" (
  "conversationId" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "tenantId" TEXT NOT NULL,
  "type" "ConversationType" NOT NULL,
  "name" TEXT,
  "description" TEXT,
  "avatarUrl" TEXT,
  "linkedTransactionId" TEXT,
  "isArchived" BOOLEAN NOT NULL DEFAULT false,
  "deletedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT now(),
  "lastMessageAt" TIMESTAMPTZ(3)
);
CREATE INDEX IF NOT EXISTS "Conversation_tenantId_type_idx" ON "Conversation"("tenantId", "type");
CREATE INDEX IF NOT EXISTS "Conversation_tenantId_lastMessageAt_idx" ON "Conversation"("tenantId", "lastMessageAt");
CREATE INDEX IF NOT EXISTS "Conversation_linkedTransactionId_idx" ON "Conversation"("linkedTransactionId");

-- ConversationParticipant table
CREATE TABLE IF NOT EXISTS "ConversationParticipant" (
  "participantId" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "tenantId" TEXT NOT NULL,
  "conversationId" TEXT NOT NULL REFERENCES "Conversation"("conversationId") ON DELETE CASCADE,
  "profileId" TEXT NOT NULL,
  "role" "ParticipantRole" NOT NULL DEFAULT 'MEMBER',
  "canSendMessages" BOOLEAN NOT NULL DEFAULT true,
  "lastReadAt" TIMESTAMPTZ(3),
  "unreadCount" INTEGER NOT NULL DEFAULT 0,
  "isMuted" BOOLEAN NOT NULL DEFAULT false,
  "muteExpiresAt" TIMESTAMPTZ(3),
  "joinedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT now(),
  "leftAt" TIMESTAMPTZ(3),
  "removedBy" TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS "ConversationParticipant_unique" ON "ConversationParticipant"("tenantId", "conversationId", "profileId");
CREATE INDEX IF NOT EXISTS "ConversationParticipant_tenantId_profileId_idx" ON "ConversationParticipant"("tenantId", "profileId");
CREATE INDEX IF NOT EXISTS "ConversationParticipant_conversationId_idx" ON "ConversationParticipant"("conversationId");

-- Message table
CREATE TABLE IF NOT EXISTS "Message" (
  "messageId" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "tenantId" TEXT NOT NULL,
  "conversationId" TEXT NOT NULL REFERENCES "Conversation"("conversationId") ON DELETE CASCADE,
  "senderProfileId" TEXT NOT NULL,
  "type" "MessageType" NOT NULL,
  "encryptedContent" TEXT NOT NULL,
  "contentNonce" TEXT NOT NULL,
  "encryptionKeyId" TEXT NOT NULL,
  "voiceDurationMs" INTEGER,
  "voiceStorageKey" TEXT,
  "voiceFileHash" TEXT,
  "linkedTransactionId" TEXT,
  "replyToMessageId" TEXT,
  "status" "MessageStatus" NOT NULL DEFAULT 'SENDING',
  "masterKeyWrappedContent" TEXT,
  "fileName" TEXT,
  "fileSize" INTEGER,
  "fileMimeType" TEXT,
  "fileStorageKey" TEXT,
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT now(),
  "editedAt" TIMESTAMPTZ(3),
  "deletedAt" TIMESTAMPTZ(3)
);
CREATE INDEX IF NOT EXISTS "Message_tenantId_conversationId_createdAt_idx" ON "Message"("tenantId", "conversationId", "createdAt");
CREATE INDEX IF NOT EXISTS "Message_senderProfileId_idx" ON "Message"("senderProfileId");
CREATE INDEX IF NOT EXISTS "Message_linkedTransactionId_idx" ON "Message"("linkedTransactionId");
CREATE INDEX IF NOT EXISTS "Message_status_idx" ON "Message"("status");

-- MessageDeliveryReceipt table
CREATE TABLE IF NOT EXISTS "MessageDeliveryReceipt" (
  "receiptId" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "tenantId" TEXT NOT NULL,
  "messageId" TEXT NOT NULL REFERENCES "Message"("messageId") ON DELETE CASCADE,
  "recipientProfileId" TEXT NOT NULL,
  "deliveredAt" TIMESTAMPTZ(3),
  "readAt" TIMESTAMPTZ(3),
  "failedAt" TIMESTAMPTZ(3),
  "failureReason" TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS "MessageDeliveryReceipt_unique" ON "MessageDeliveryReceipt"("messageId", "recipientProfileId");
CREATE INDEX IF NOT EXISTS "MessageDeliveryReceipt_tenantId_recipientProfileId_idx" ON "MessageDeliveryReceipt"("tenantId", "recipientProfileId");

-- UserSignalKey table
CREATE TABLE IF NOT EXISTS "UserSignalKey" (
  "keyId" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "tenantId" TEXT NOT NULL,
  "profileId" TEXT NOT NULL,
  "identityKeyPublic" TEXT NOT NULL,
  "identityKeyPrivate" TEXT NOT NULL,
  "registrationId" INTEGER NOT NULL,
  "signedPreKeyId" INTEGER NOT NULL,
  "signedPreKeyPublic" TEXT NOT NULL,
  "signedPreKeyPrivate" TEXT NOT NULL,
  "signedPreKeySignature" TEXT NOT NULL,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT now(),
  "revokedAt" TIMESTAMPTZ(3)
);
CREATE UNIQUE INDEX IF NOT EXISTS "UserSignalKey_unique" ON "UserSignalKey"("tenantId", "profileId", "isActive");
CREATE INDEX IF NOT EXISTS "UserSignalKey_profileId_idx" ON "UserSignalKey"("profileId");

-- SignalPreKey table
CREATE TABLE IF NOT EXISTS "SignalPreKey" (
  "preKeyId" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "tenantId" TEXT NOT NULL,
  "userKeyId" TEXT NOT NULL REFERENCES "UserSignalKey"("keyId") ON DELETE CASCADE,
  "keyIndex" INTEGER NOT NULL,
  "publicKey" TEXT NOT NULL,
  "privateKey" TEXT NOT NULL,
  "isUsed" BOOLEAN NOT NULL DEFAULT false,
  "usedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS "SignalPreKey_unique" ON "SignalPreKey"("userKeyId", "keyIndex");
CREATE INDEX IF NOT EXISTS "SignalPreKey_tenantId_isUsed_idx" ON "SignalPreKey"("tenantId", "isUsed");

-- GroupEncryptionKey table
CREATE TABLE IF NOT EXISTS "GroupEncryptionKey" (
  "keyId" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "tenantId" TEXT NOT NULL,
  "conversationId" TEXT NOT NULL REFERENCES "Conversation"("conversationId") ON DELETE CASCADE,
  "keyVersion" INTEGER NOT NULL,
  "createdByProfileId" TEXT NOT NULL,
  "masterKeyWrapped" TEXT NOT NULL,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT now(),
  "rotatedAt" TIMESTAMPTZ(3)
);
CREATE UNIQUE INDEX IF NOT EXISTS "GroupEncryptionKey_unique" ON "GroupEncryptionKey"("conversationId", "keyVersion");
CREATE INDEX IF NOT EXISTS "GroupEncryptionKey_tenantId_conversationId_isActive_idx" ON "GroupEncryptionKey"("tenantId", "conversationId", "isActive");

-- GroupParticipantKey table
CREATE TABLE IF NOT EXISTS "GroupParticipantKey" (
  "participantKeyId" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "tenantId" TEXT NOT NULL,
  "groupKeyId" TEXT NOT NULL REFERENCES "GroupEncryptionKey"("keyId") ON DELETE CASCADE,
  "profileId" TEXT NOT NULL,
  "wrappedKey" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS "GroupParticipantKey_unique" ON "GroupParticipantKey"("groupKeyId", "profileId");
CREATE INDEX IF NOT EXISTS "GroupParticipantKey_tenantId_profileId_idx" ON "GroupParticipantKey"("tenantId", "profileId");
