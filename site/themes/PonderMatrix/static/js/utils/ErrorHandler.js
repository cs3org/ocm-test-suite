export class ErrorHandler {
    static ERROR_TYPES = {
        NETWORK: 'NETWORK',
        INITIALIZATION: 'INITIALIZATION',
        COMPONENT: 'COMPONENT',
        RUNTIME: 'RUNTIME'
    };

    constructor(options = {}) {
        this.options = {
            enableLogging: true,
            maxRetries: 3,
            ...options
        };
        this.errorLog = [];
    }

    handleError(error, type = ErrorHandler.ERROR_TYPES.RUNTIME) {
        const errorInfo = {
            timestamp: new Date(),
            type,
            message: error.message,
            stack: error.stack,
            metadata: {}
        };

        if (error.response) {
            errorInfo.metadata.status = error.response.status;
            errorInfo.metadata.statusText = error.response.statusText;
        }

        this.logError(errorInfo);
        return this.determineRecoveryStrategy(errorInfo);
    }

    logError(errorInfo) {
        if (this.options.enableLogging) {
            this.errorLog.push(errorInfo);
            console.error(`[${errorInfo.type}] ${errorInfo.message}`, errorInfo);
        }
    }

    determineRecoveryStrategy(errorInfo) {
        switch (errorInfo.type) {
            case ErrorHandler.ERROR_TYPES.NETWORK:
                return {
                    action: 'retry',
                    message: 'Network error occurred. Retrying...'
                };
            case ErrorHandler.ERROR_TYPES.INITIALIZATION:
                return {
                    action: 'notify',
                    message: 'Initialization failed. Artifacts may not be available in local development.'
                };
            default:
                return {
                    action: 'notify',
                    message: 'An error occurred. Please try again.'
                };
        }
    }

    getErrorLog() {
        return [...this.errorLog];
    }

    clearErrorLog() {
        this.errorLog = [];
    }
} 