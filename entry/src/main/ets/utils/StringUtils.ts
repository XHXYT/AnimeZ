
class stringUtils {

  public splitString(input: string, sign: string): { first: string, second: string } {
    const [first, second] = input.split(sign)
    return { first, second };
  }

}

export const StringUtils = new stringUtils()