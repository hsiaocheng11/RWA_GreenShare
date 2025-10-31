// FILE: lib/hooks/useImTokenDetection.ts
import { useState, useEffect } from 'react';

interface ImTokenDetectionResult {
  isAvailable: boolean;
  isInstalled: boolean;
  isMobile: boolean;
  userAgent: string;
  platform: 'ios' | 'android' | 'desktop' | 'unknown';
  version?: string;
}

export function useImTokenDetection(): ImTokenDetectionResult {
  const [detection, setDetection] = useState<ImTokenDetectionResult>({
    isAvailable: false,
    isInstalled: false,
    isMobile: false,
    userAgent: '',
    platform: 'unknown'
  });

  useEffect(() => {
    const detectImToken = () => {
      const userAgent = navigator.userAgent.toLowerCase();
      
      // Detect platform
      let platform: 'ios' | 'android' | 'desktop' | 'unknown' = 'unknown';
      if (/iphone|ipad|ipod/.test(userAgent)) {
        platform = 'ios';
      } else if (/android/.test(userAgent)) {
        platform = 'android';
      } else if (!/mobile/.test(userAgent)) {
        platform = 'desktop';
      }

      // Check if mobile device
      const isMobile = /android|webos|iphone|ipad|ipod|blackberry|iemobile|opera mini/i.test(userAgent);
      
      // Check if imToken is installed (via User Agent)
      const isImTokenUA = userAgent.includes('imtoken');
      
      // Check if running in imToken browser
      const isImTokenBrowser = window.location.href.includes('imtoken') || 
                              (window as any).imToken !== undefined ||
                              userAgent.includes('imtoken');

      // Check if deep links are supported
      const supportsDeepLinks = isMobile || platform !== 'desktop';
      
      // Extract imToken version if available
      let version: string | undefined;
      const versionMatch = userAgent.match(/imtoken\/(\d+\.\d+\.\d+)/);
      if (versionMatch) {
        version = versionMatch[1];
      }

      setDetection({
        isAvailable: supportsDeepLinks,
        isInstalled: isImTokenUA || isImTokenBrowser,
        isMobile,
        userAgent: navigator.userAgent,
        platform,
        version
      });
    };

    detectImToken();

    // Listen for orientation changes on mobile
    const handleOrientationChange = () => {
      setTimeout(detectImToken, 100);
    };

    window.addEventListener('orientationchange', handleOrientationChange);
    
    return () => {
      window.removeEventListener('orientationchange', handleOrientationChange);
    };
  }, []);

  return detection;
}

// Hook for testing deep link functionality
export function useImTokenDeepLinkTest() {
  const [lastTestResult, setLastTestResult] = useState<{
    success: boolean;
    timestamp: Date;
    link: string;
    error?: string;
  } | null>(null);

  const testDeepLink = async (link: string): Promise<boolean> => {
    try {
      // Create a hidden iframe to test the deep link
      const iframe = document.createElement('iframe');
      iframe.style.display = 'none';
      iframe.src = link;
      document.body.appendChild(iframe);

      // Wait a moment then remove the iframe
      setTimeout(() => {
        document.body.removeChild(iframe);
      }, 1000);

      // On mobile, attempt to open the link directly
      if (window.location.href.includes('mobile') || /android|iphone|ipad|ipod/i.test(navigator.userAgent)) {
        window.location.href = link;
      }

      setLastTestResult({
        success: true,
        timestamp: new Date(),
        link
      });

      return true;
    } catch (error) {
      setLastTestResult({
        success: false,
        timestamp: new Date(),
        link,
        error: error instanceof Error ? error.message : 'Unknown error'
      });

      return false;
    }
  };

  return {
    testDeepLink,
    lastTestResult
  };
}