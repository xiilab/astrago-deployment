package com.xiilab.keycloak.spi;

import org.keycloak.Config;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.EventListenerProviderFactory;
import org.keycloak.models.KeycloakSession;

public class AstragoEventListenerProviderFactory implements EventListenerProviderFactory {
    
    public static final String PROVIDER_ID = "astrago-event-listener";

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public EventListenerProvider create(KeycloakSession session) {
        return new AstragoEventListenerProvider(session);
    }

    @Override
    public void init(Config.Scope config) {
        // Nothing to initialize
    }

    @Override
    public void postInit(org.keycloak.models.KeycloakSessionFactory factory) {
        // Nothing to post-initialize
    }

    @Override
    public void close() {
        // Nothing to close
    }
} 