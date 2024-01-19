interface ILambdaConfig {
    [key: string]: string|number|boolean|null;
}

export const config: ILambdaConfig = {
    env: loadFromEnv('NODE_ENV', 'development'),
};

function loadFromEnv(variable: string, defaultValue: string|number|null|undefined = undefined) {
    const value = process.env && process.env[variable];

    return value || defaultValue;
}
